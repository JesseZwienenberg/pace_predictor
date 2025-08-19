class AllTimeBestEffort < ApplicationRecord
  belongs_to :activity, optional: true
  
  validates :distance_meters, presence: true, uniqueness: true
  validates :pace_min_per_km, presence: true
  
  scope :by_distance, -> { order(:distance_meters) }
  scope :for_distance_range, ->(from, to) { where(distance_meters: from..to) }
  
  # Get data formatted for charting
  def self.for_chart(max_distance_meters = nil)
    query = max_distance_meters ? where('distance_meters <= ?', max_distance_meters) : all
    query.by_distance.pluck(:distance_meters, :pace_min_per_km)
  end
end