# app/models/cached_segment.rb
class CachedSegment < ApplicationRecord
  def kom_pace
    (kom_time / 60.0) / (distance / 1000.0) if kom_time && distance
  end

  def difficulty_ratio
    SegmentAnalyzer.difficulty_ratio(distance, kom_time) if distance && kom_time
  end

  def self.near_location(lat, lng, radius_km)
    # Convert km to degrees (rough approximation)
    lat_range = radius_km / 111.0
    lng_range = radius_km / (111.0 * Math.cos(lat * Math::PI / 180))
    
    where(
      start_latitude: (lat - lat_range)..(lat + lat_range),
      start_longitude: (lng - lng_range)..(lng + lng_range)
    ).where.not(start_latitude: nil, start_longitude: nil)
  end

  def self.with_filters(max_distance_m: nil, max_pace_min_km: nil)
    scope = all
    scope = scope.where('distance <= ?', max_distance_m) if max_distance_m
    
    if max_pace_min_km
      # kom_pace = (kom_time / 60.0) / (distance / 1000.0)
      # kom_pace >= max_pace_min_km
      # (kom_time / 60.0) / (distance / 1000.0) >= max_pace_min_km
      # kom_time / 60.0 >= max_pace_min_km * (distance / 1000.0)
      # kom_time >= max_pace_min_km * distance / 1000.0 * 60.0
      # kom_time >= max_pace_min_km * distance * 0.06
      scope = scope.where('kom_time >= (? * distance * 0.06)', max_pace_min_km)
    end
    
    scope
  end
end