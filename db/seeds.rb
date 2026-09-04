# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# db/seeds.rb
puts "🧹 Cleaning database..."
Walk.destroy_all
Journey.destroy_all
User.destroy_all

LE_WAGON_MEGURO_LAT = 35.63401173196464
LE_WAGON_MEGURO_LNG = 139.70812599610076

puts "👤 Creating user..."
user = User.create!(
  email: "matt@mail.com",
  name: "Matt",
  password: "qwerty",
  current_latitude: LE_WAGON_MEGURO_LAT,
  current_longitude: LE_WAGON_MEGURO_LNG,
  current_location_name: "Le Wagon Tokyo, Meguro"
)

puts "🗺️  Generating journeys via Mapbox..."

# Plain synthetic-loop generation (JourneyGenerator directly, no theme/POI/LLM
# involved) -- target_distance_meters and a synthetic loop around (lat, lng),
# then just labeled with a name/description by hand. Returns the successfully
# generated Journeys (already saved: true, community-visible).
def generate_journeys(lat:, lng:, specs:)
  specs.filter_map do |spec|
    result = JourneyGenerator.new(lat: lat, lng: lng, target_distance_meters: spec[:distance]).call

    if result.success?
      journey = result.journey
      # ~0.75m average stride length
      estimated_steps = (journey.distance_meters / 0.75).round
      journey.update!(name: spec[:name], description: spec[:description], estimated_steps: estimated_steps, recommendable: true)
      puts "  ✅ #{spec[:name]} (#{journey.distance_meters.round}m, ~#{estimated_steps} steps, " \
           "#{(journey.estimated_duration_seconds / 60.0).round} min)"
      journey
    else
      puts "  ❌ #{spec[:name]} failed: #{result.error}"
      nil
    end
  end
end

journey_specs = [
  { name: "Riverside Stroll", description: "A calm loop tracing the river, plenty of greenery.", distance: 1600 },
  { name: "Park Escape",      description: "Quiet, mostly shaded park paths.",                     distance: 1300 },
  { name: "Morning Refresh",  description: "A longer wander through open, active streets.",         distance: 1700 }
]

journeys = generate_journeys(lat: 35.63410765097896, lng: 139.7081474537728, specs: journey_specs) # Le Wagon, Tokyo

if journeys.empty?
  puts "⚠️  No journeys were generated — check your Mapbox token before seeding walks."
else
  puts "🚶 Creating walk history..."

  walk_specs = [
    { journey: journeys[0], started_at: Time.zone.now - 1.hour, duration: 24.minutes, mood: "Calm", steps: 2400, distance: 1.9, reflection: "Nice breeze by the river, felt great." },
    { journey: journeys[1], started_at: 2.days.ago,              duration: 20.minutes, mood: "Neutral",   steps: 2100, distance: 1.6, reflection: "Quick stroll after lunch." },
    { journey: journeys[2], started_at: 4.days.ago,              duration: 18.minutes, mood: "Calm", steps: 1700, distance: 1.3, reflection: "Needed to clear my head before a meeting." },
    { journey: journeys[0], started_at: 6.days.ago,              duration: 22.minutes, mood: "Good",   steps: 2300, distance: 1.7, reflection: "Morning walk before work, good start." },
    { journey: journeys[1], started_at: 8.days.ago,          duration: 25.minutes, mood: "Energised",   steps: 2600, distance: 2.0, reflection: "A bit tired, but glad I went." }
  ]

  walk_specs.each do |w|
    next unless w[:journey]

    Walk.create!(
      user: user,
      journey: w[:journey],
      started_at: w[:started_at],
      completed_at: w[:started_at] + w[:duration],
      actual_distance: w[:distance],
      actual_steps: w[:steps],
      mood_after: w[:mood],
      reflection: w[:reflection]
    )
  end

  puts "✅ #{Walk.count} walks created for #{user.name}"
end

puts "🗾 Generating more community routes in Meguro-ku..."

meguro_journey_specs = [
  { name: "Meguro River Loop",       description: "A gentle loop along the river, shaded by rows of trees.",       distance: 1500 },
  { name: "Nakameguro Backstreets",  description: "Quiet residential lanes tucked behind the main road.",          distance: 1400 },
  { name: "Yutenji Green Escape",    description: "A calm stretch past small parks and tree-lined sidewalks.",     distance: 1800 }
]

generate_journeys(lat: 35.6414, lng: 139.6982, specs: meguro_journey_specs) # Meguro-ku, Tokyo

puts "🎨 Generating themed journeys for the mood picker at Le Wagon Meguro..."

# theme_key -> rough compass bearing (degrees, 0 = north) toward a real feature in that
# direction from Le Wagon Meguro, so each theme's synthetic route leans somewhere plausible
# instead of a bearing chosen uniformly at random. Best-effort, not exact POI targeting --
# the real POI-based curation (RouteBuilder/PoiFinder/LlmPoiCurator) is still in development.
THEME_BEARINGS = {
  calm: 315,     # NW, away from the main road into quieter residential blocks
  refresh: 200,  # S/SSW, toward the Meguro River green corridor
  cheerful: 90,  # E, toward the Meguro-dori shopping stretch
  recharge: 135  # SE, toward the larger green space in that direction
}.freeze

THEME_JOURNEY_COPY = {
  calm: { name: "Calm Backstreets",
          description: "Quiet residential lanes away from traffic, at an unhurried pace." },
  refresh: { name: "Riverside Refresh",
             description: "Open air alongside the river, a scenic outlook and a brisker pace." },
  cheerful: { name: "Meguro-dori Stroll",
              description: "Everyday street life and small, colorful moments along a busier stretch." },
  recharge: { name: "Green Recharge",
              description: "Dense greenery and distance from noise, with room to slow down." }
}.freeze

# minutes: nil means "No rush" (the duration sheet's blank option) -- there's no fixed target
# in the live pipeline for that case either, so it's just seeded with a longer distance.
DURATION_BUCKETS = [10, 20, 30, nil].freeze

# JourneyGenerator fails outright (no internal retry) if a single synthetic waypoint can't be
# routed to, and even on success its own internal rescale-and-retry gives up after 3 tries and
# returns whatever it has -- at small radii (short durations, e.g. 10 min loops in this dense
# street grid) actual distance vs. target is noisy even across fresh attempts (observed ratios
# from 0.3x to 1.8x of target in back-to-back calls). So: keep retrying with brand new (freshly
# jittered) calls and track whichever attempt lands closest to the target distance, not just the
# first one that didn't error. This is a one-time offline seed run, so spending extra Mapbox
# calls here to reliably land a good pick is cheap.
def generate_themed_journey(theme_key:, minutes:, max_attempts: 12)
  copy = THEME_JOURNEY_COPY.fetch(theme_key)
  target_minutes = minutes || 45
  target_distance = target_minutes * RouteBuilder::WALKING_METERS_PER_MINUTE
  label = minutes ? "#{minutes} min" : "No rush"

  best_result = nil
  best_off_by = nil
  max_attempts.times do
    result = JourneyGenerator.new(
      lat: LE_WAGON_MEGURO_LAT,
      lng: LE_WAGON_MEGURO_LNG,
      target_distance_meters: target_distance,
      theme_key: theme_key.to_s,
      name: "#{copy[:name]} · #{label}",
      description: copy[:description],
      base_bearing: THEME_BEARINGS.fetch(theme_key)
    ).call
    next unless result.success?

    off_by = ((result.journey.distance_meters / target_distance) - 1).abs
    best_result, best_off_by = result, off_by if best_off_by.nil? || off_by < best_off_by
    break if off_by <= JourneyGenerator::TOLERANCE_RATIO
  end
  result = best_result || JourneyGenerator::Result.new(success?: false, error: "no successful attempt")

  if result.success?
    journey = result.journey
    journey.update!(estimated_steps: (journey.distance_meters / 0.75).round, recommendable: true)
    puts "  ✅ #{journey.name} (#{journey.distance_meters.round}m, " \
         "#{(journey.estimated_duration_seconds / 60.0).round} min)"
  else
    puts "  ❌ #{copy[:name]} · #{label} failed after #{max_attempts} attempts: #{result&.error}"
  end

  result
end

THEME_BEARINGS.each_key do |theme_key|
  DURATION_BUCKETS.each { |minutes| generate_themed_journey(theme_key: theme_key, minutes: minutes) }
end

puts "🌱 Done seeding!"
