class Activity < ApplicationRecord
  has_many :splits, dependent: :destroy
  has_many :best_efforts, dependent: :destroy

  after_save :update_all_time_best_efforts, if: :saved_change_to_all_best_efforts?

  def pace_per_km
      return 0 if distance.zero?
      (duration / 60.0) / (distance / 1000.0)
  end

  def distance_km
      distance / 1000.0
  end

  private
  
  def update_all_time_best_efforts
    return if all_best_efforts.blank?
    
    records_to_update = []
    
    all_best_efforts.each_with_index do |pace, index|
      next if pace.nil?
      
      distance_meters = (index + 1) * 10
      
      record = AllTimeBestEffort.find_or_initialize_by(distance_meters: distance_meters)
      
      if record.new_record? || pace < record.pace_min_per_km
        record.pace_min_per_km = pace
        record.activity = self
        record.achieved_at = start_date
        records_to_update << record
      end
    end
    
    ActiveRecord::Base.transaction do
      records_to_update.each(&:save!)
    end
    
    records_to_update.size
  end
end
