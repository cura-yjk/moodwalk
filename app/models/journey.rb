class Journey < ApplicationRecord
  has_many :walks

  # find routes within `radius_meters` of a point, closest first
  scope :near, lambda { |lat, lng, radius_meters = 3000|
    point = RGeo::Geographic.spherical_factory(srid: 4326).point(lng, lat)
    where("ST_DWithin(start_point, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)", lng, lat, radius_meters)
      .order(Arel.sql("start_point <-> ST_SetSRID(ST_MakePoint(#{lng}, #{lat}), 4326)::geography"))
  }
end
