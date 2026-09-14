namespace :journeys do
  # One-off backfill for journeys created before JourneyGenerator started
  # setting location_name at creation time. Journey#location_name used to do
  # this lazily on read, which put a blocking Mapbox call and an UPDATE inside
  # the card-rendering loop -- see app/models/journey.rb.
  desc "Reverse-geocode a neighborhood label for journeys missing one"
  task backfill_location_names: :environment do
    scope = Journey.where(location_name: [nil, ""])
    total = scope.count
    puts "Backfilling #{total} journey location name(s)..."

    filled = 0
    scope.find_each do |journey|
      name = MapboxGeocoder.reverse(journey.start_point.y, journey.start_point.x)
      if name
        journey.update_column(:location_name, name)
        filled += 1
      else
        warn "  journey #{journey.id}: no name returned"
      end
    end

    puts "Done: #{filled}/#{total} filled."
  end
end
