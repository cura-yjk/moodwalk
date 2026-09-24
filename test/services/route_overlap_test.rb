require "test_helper"

class RouteOverlapTest < ActiveSupport::TestCase
  START = { lat: 35.634, lng: 139.708 }.freeze

  test "a route that never crosses its own path re-walks nothing" do
    assert_in_delta 0.0, RouteOverlap.ratio(line(0, 800)), 0.02
  end

  test "walking out and straight back re-walks the whole return leg" do
    out = line(0, 500)
    back = out.reverse

    assert_in_delta 0.5, RouteOverlap.ratio(out + back), 0.05
  end

  test "a loop round a block re-walks nothing" do
    corners = [0, 90, 180, 270].map { |bearing| GeoDistance.destination_point(START[:lat], START[:lng], 300, bearing) }
    square = (corners + [corners.first]).map { |point| [point[:lng], point[:lat]] }

    assert_in_delta 0.0, RouteOverlap.ratio(square), 0.02
  end

  test "a short spur in and out of a long route counts only the way back out" do
    main = line(0, 1000)
    spur_base = main.last
    spur_end = GeoDistance.destination_point(spur_base[1], spur_base[0], 50, 90)
    route = main + [[spur_end[:lng], spur_end[:lat]], spur_base]

    # 50m of the ~1100m walked is the way back out of the spur.
    assert_in_delta 0.045, RouteOverlap.ratio(route), 0.03
  end

  test "a route too short to measure re-walks nothing" do
    assert_equal 0.0, RouteOverlap.ratio([])
    assert_equal 0.0, RouteOverlap.ratio([[START[:lng], START[:lat]]])
  end

  private

  # [lng, lat] pairs every 50m along a bearing, the shape a decoded polyline has.
  def line(bearing, length)
    (0..length).step(50).map do |meters|
      point = GeoDistance.destination_point(START[:lat], START[:lng], meters, bearing)
      [point[:lng], point[:lat]]
    end
  end
end
