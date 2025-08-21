# app/models/cached_segment.rb
class CachedSegment < ApplicationRecord
  def kom_pace
    (kom_time / 60.0) / (distance / 1000.0) if kom_time && distance
  end
end