class RecordsController < ApplicationController
  def index
    @personal_records = calculate_personal_records
    @chart_data = prepare_chart_data
    
    @exponent = (params[:exponent] || 1.06).to_f
    @best_riegel_data, @worst_riegel_data, @avg_riegel_data = calculate_riegel_data(@exponent)

    # Handle AJAX requests for updating chart
    respond_to do |format|
      format.html # Regular page load
      format.json do
        render json: {
          best_riegel_data: @best_riegel_data,
          avg_riegel_data: @avg_riegel_data,
          worst_riegel_data: @worst_riegel_data,
          exponent: @exponent
        }
      end
    end
  end

  private

  def calculate_personal_records
    records = {}
    
    BestEffort.joins(:activity)
              .group(:name)
              .minimum(:elapsed_time)
              .each do |distance_name, best_time|
      
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
    '1/2 mile' => 0.804672,
    '1K' => 1.0,
    '1 mile' => 1.609344,
    '2K' => 2.0,
    '2 mile' => 3.218688,
    '5K' => 5.0,
    '10K' => 10.0,
    '15K' => 15.0,
    'Half Marathon' => 21.0975,
    'Marathon' => 42.195
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

  def calculate_riegel_data(exponent)
    best_ratio = 0
    worst_ratio = 0
    ratio_sum = 0

    exponent_new = exponent - 1

    @chart_data.each do |val|
      ratio = val[:y] * val[:x]**-exponent_new

      ratio_sum += ratio
      if best_ratio == 0 || ratio < best_ratio
        best_ratio = ratio
      end
      if ratio > worst_ratio
        worst_ratio = ratio
      end
    end
    
    [
      @chart_data.map { |point| point.merge(y: best_ratio * point[:x]**exponent_new) },
      @chart_data.map { |point| point.merge(y: worst_ratio * point[:x]**exponent_new) },
      @chart_data.map { |point| point.merge(y: ratio_sum / @chart_data.count * point[:x]**exponent_new) },
    ]
  end
end