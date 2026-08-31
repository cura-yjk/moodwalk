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

puts "👤 Creating user..."
user = User.create!(email: "twinky@mail.com", name: "Twinky", password: "qwerty")

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
      journey.update!(name: spec[:name], description: spec[:description], estimated_steps: estimated_steps, saved: true)
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
    { journey: journeys[0], started_at: 2.days.ago,              duration: 20.minutes, mood: "Neutral",   steps: 2100, distance: 1.6, reflection: "Quick stroll after lunch." },
    { journey: journeys[1], started_at: 4.days.ago,              duration: 18.minutes, mood: "Calm", steps: 1700, distance: 1.3, reflection: "Needed to clear my head before a meeting." },
    { journey: journeys[2], started_at: 6.days.ago,              duration: 22.minutes, mood: "Good",   steps: 2300, distance: 1.7, reflection: "Morning walk before work, good start." },
    { journey: journeys.sample, started_at: 8.days.ago,          duration: 25.minutes, mood: "Energised",   steps: 2600, distance: 2.0, reflection: "A bit tired, but glad I went." }
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

puts "🌱 Done seeding!"
