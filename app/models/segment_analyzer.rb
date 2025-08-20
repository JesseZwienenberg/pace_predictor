# app/models/segment_analyzer.rb
class SegmentAnalyzer
  def self.difficulty_ratio(segment_distance_m, kom_time_s)
    distance_key = (segment_distance_m / 10.0).round * 10
    
    my_effort = AllTimeBestEffort.find_by(distance_meters: distance_key)
    return nil unless my_effort
    
    kom_pace = (kom_time_s / 60.0) / (segment_distance_m / 1000.0)
    kom_pace / my_effort.pace_min_per_km
  end
end