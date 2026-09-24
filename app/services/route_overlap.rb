# How much of a route re-walks ground it has already covered, as a share of
# its length (0-1).
#
# This is what a walker experiences as backtracking, and it only shows in the
# route Mapbox returns: a spur in and out of a park, or a street walked twice
# on the way between two waypoints, never appears in the straight-line
# waypoint plan PoiSelector scores. Measured on real routes, anything past
# about a tenth is noticeably retraced; loops that go round cleanly come in
# under 5%.
module RouteOverlap
  module_function

  # Samples are evenly spaced along the route so a stretch with dense
  # polyline vertices doesn't count for more than a straight one.
  SAMPLE_STEP_METERS = 10

  # Close enough to be the same street - roughly a street's width.
  SAME_STREET_METERS = 12

  # Only ground walked at least this long ago counts as already covered;
  # otherwise every sample would match the ones just before it, and so would
  # the far side of an ordinary street corner.
  RECENT_METERS = 30

  # coordinates are [lng, lat] pairs, as RouteGeometry#route_coordinates
  # gives them.
  def ratio(coordinates)
    samples = resample(project(coordinates))
    return 0.0 if samples.size < 2

    rewalked = count_rewalked(samples)
    rewalked.fdiv(samples.size)
  end

  # Counts samples lying on ground walked more than RECENT_METERS earlier.
  # Earlier samples go into a grid of SAME_STREET_METERS cells only once
  # they're old enough to count, so each check looks at nine cells rather than
  # the whole route.
  def count_rewalked(samples)
    grid = Hash.new { |hash, key| hash[key] = [] }
    waiting = 0

    samples.count do |point, along|
      while samples[waiting][1] < along - RECENT_METERS
        grid[cell(samples[waiting][0])] << samples[waiting][0]
        waiting += 1
      end

      walked_before?(grid, point)
    end
  end

  def walked_before?(grid, point)
    neighbours(point).any? do |key|
      grid.fetch(key, []).any? { |earlier| distance(point, earlier) <= SAME_STREET_METERS }
    end
  end

  def cell((east, north))
    [(east / SAME_STREET_METERS).floor, (north / SAME_STREET_METERS).floor]
  end

  def neighbours(point)
    column, row = cell(point)
    [-1, 0, 1].product([-1, 0, 1]).map { |across, up| [column + across, row + up] }
  end

  def distance((east1, north1), (east2, north2))
    Math.hypot(east2 - east1, north2 - north1)
  end

  # Metres east and north of the first point, which the grid can bucket.
  def project(coordinates)
    return [] if coordinates.blank?

    origin_lng, origin_lat = coordinates.first
    coordinates.map { |lng, lat| GeoDistance.local_offset(origin_lat, origin_lng, lat, lng) }
  end

  # Points every SAMPLE_STEP_METERS along the route, each paired with its
  # distance along it.
  def resample(points)
    return [] if points.empty?

    samples = [[points.first, 0.0]]
    walked = 0.0

    points.each_cons(2) do |from, to|
      length = distance(from, to)
      samples.concat(samples_along(from, to, walked, length, samples.last[1]))
      walked += length
    end

    samples
  end

  # The samples falling on one segment, which starts `walked` metres along
  # the route; `last_at` is where the previous sample fell.
  def samples_along(from, to, walked, length, last_at)
    return [] unless length.positive?

    at = last_at + SAMPLE_STEP_METERS
    (at..(walked + length)).step(SAMPLE_STEP_METERS).map do |along|
      share = (along - walked) / length
      [[from[0] + ((to[0] - from[0]) * share), from[1] + ((to[1] - from[1]) * share)], along.to_f]
    end
  end
end
