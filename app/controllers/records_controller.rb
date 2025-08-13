class RecordsController < ApplicationController
  def index
    @personal_records = calculate_personal_records
  end

  private

  def calculate_personal_records
    records = {}
    
    # Get all best efforts and find the fastest for each distance
    BestEffort.joins(:activity)
              .group(:name)
              .minimum(:elapsed_time)
              .each do |distance_name, best_time|
      
      # Find the activity where this record was set
      best_effort = BestEffort.joins(:activity)
                            .where(name: distance_name, elapsed_time: best_time)
                            .includes(:activity)
                            .first
      
      if best_effort
        records[distance_name] = {
          time: best_time,
          pace: (best_time / 60.0) / (best_effort.distance / 1000.0), # min/km
          activity: best_effort.activity,
          date: best_effort.activity.start_date
        }
      end
    end
    
    records.sort_by { |name, data| distance_sort_order(name) }
  end

  def distance_sort_order(distance_name)
    order = {
      '400m' => 1, 
      '1/2 mile' => 2, 
      '1K' => 3, 
      '1 mile' => 4,
      '2K' => 5,
      '2 mile' => 6,
      '5K' => 7, 
      '10K' => 8, 
      '15K' => 9, 
      'Half Marathon' => 10, 
      'Marathon' => 11
    }
    order[distance_name] || 999
  end
end