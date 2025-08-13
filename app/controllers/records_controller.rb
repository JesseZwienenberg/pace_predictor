class RecordsController < ApplicationController
  def index
    @personal_records = calculate_personal_records
    @chart_data = prepare_chart_data
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
          pace: (best_time / 60.0) / (best_effort.distance / 1000.0),
          activity: best_effort.activity,
          date: best_effort.activity.start_date
        }
      end
    end
    
    # Return sorted array instead of hash
    records.sort_by { |name, data| distance_sort_order(name) }
  end

  def prepare_chart_data
    @personal_records.map do |name, record|
      {
        x: distance_to_km(name),
        y: record[:pace].round(2),
        label: name
      }
    end
  end

  def distance_to_km(distance_name)
    conversions = {
      '400m' => 0.4,
      '1/2 mile' => 0.8,
      '1K' => 1.0,
      '1 mile' => 1.6,
      '2K' => 2.0,
      '2 mile' => 3.2,
      '5K' => 5.0,
      '10K' => 10.0,
      '15K' => 15.0,
      'Half Marathon' => 21.1,
      'Marathon' => 42.2
    }
    conversions[distance_name] || 0
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