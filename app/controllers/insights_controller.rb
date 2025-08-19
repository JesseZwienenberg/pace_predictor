class InsightsController < ApplicationController
  def index
    @filtered_activities = Activity.where("name NOT ILIKE ? AND name NOT ILIKE ?", "%interval%", "%herstel%")
    @filtered_splits = Split.where("name NOT ILIKE ? AND name NOT ILIKE ?", "%interval%", "%herstel%")

    @best_day_of_week = calculate_best_day_of_week
    @best_time_of_day = calculate_best_time_of_day
    @monthly_trends = calculate_monthly_trends
    @weekend_vs_weekday = calculate_weekend_vs_weekday
    @rest_day_impact = calculate_rest_day_impact
    @pace_consistency = calculate_pace_consistency
    @within_run_pace_consistency = calculate_within_run_pace_consistency
  end

  private

  def calculate_best_day_of_week
    pace_and_count = @filtered_activities.group("EXTRACT(dow FROM start_date)")
                            .select("EXTRACT(dow FROM start_date) as dow, 
                                    AVG(duration::float / (distance / 1000.0) / 60.0) as avg_pace,
                                    COUNT(*) as run_count")
    
    total_runs = @filtered_activities.count.to_f
    
    # Convert to hash with day names
    results = {}
    pace_and_count.each do |result|
      day_name = Date::DAYNAMES[result.dow.to_i]
      percentage = (result.run_count / total_runs * 100)
      results[day_name] = {
        pace: result.avg_pace,
        count: result.run_count,
        percentage: percentage
      }
    end
    
    results
  end

  def calculate_best_time_of_day
    time_windows = {
      "00:00-04:00" => [0, 1, 2, 3],
      "04:00-08:00" => [4, 5, 6, 7],
      "08:00-12:00" => [8, 9, 10, 11],
      "12:00-16:00" => [12, 13, 14, 15],
      "16:00-20:00" => [16, 17, 18, 19],
      "20:00-24:00" => [20, 21, 22, 23]
    }
    
    total_runs = @filtered_activities.count.to_f
    results = {}
    
    time_windows.each do |window_name, hours|
      activities = @filtered_activities.where("EXTRACT(hour FROM (start_date AT TIME ZONE 'UTC' AT TIME ZONE 'Europe/Amsterdam')) IN (?)", hours)
      count = activities.count
      
      if count > 0
        avg_pace = activities.average("duration::float / (distance / 1000.0) / 60.0")
        percentage = (count / total_runs * 100)
        
        results[window_name] = {
          pace: avg_pace,
          count: count,
          percentage: percentage
        }
      end
    end
    
    results
  end

  def calculate_monthly_trends
    # Get pace by month-year, ordered chronologically
    monthly_data = Activity.group(Arel.sql("TO_CHAR(start_date, 'YYYY-MM')"))
                          .select(Arel.sql("TO_CHAR(start_date, 'YYYY-MM') as month_year,
                                  AVG(duration::float / (distance / 1000.0) / 60.0) as avg_pace,
                                  COUNT(*) as run_count,
                                  SUM(distance) / 1000.0 as total_distance"))
                          .order(Arel.sql("TO_CHAR(start_date, 'YYYY-MM') DESC"))
    
    results = {}
    monthly_data.each do |data|
      # Convert YYYY-MM to a nicer format
      year, month = data.month_year.split('-')
      month_name = Date::MONTHNAMES[month.to_i]
      display_name = "#{month_name} #{year}"
      
      results[display_name] = {
        pace: data.avg_pace,
        count: data.run_count,
        distance: data.total_distance.round(1)
      }
    end
    
    results
  end

  def calculate_weekend_vs_weekday
    total_runs = @filtered_activities.count.to_f
    
    weekend_activities = @filtered_activities.where("EXTRACT(dow FROM start_date) IN (0, 6)")
    weekend_pace = weekend_activities.average("duration::float / (distance / 1000.0) / 60.0")
    weekend_count = weekend_activities.count
    weekend_percentage = (weekend_count / total_runs * 100)
    
    weekday_activities = @filtered_activities.where("EXTRACT(dow FROM start_date) BETWEEN 1 AND 5")
    weekday_pace = weekday_activities.average("duration::float / (distance / 1000.0) / 60.0")
    weekday_count = weekday_activities.count
    weekday_percentage = (weekday_count / total_runs * 100)
    
    {
      weekend: {
        pace: weekend_pace,
        count: weekend_count,
        percentage: weekend_percentage
      },
      weekday: {
        pace: weekday_pace,
        count: weekday_count,
        percentage: weekday_percentage
      }
    }
  end

  def calculate_rest_day_impact
    results = {}
    activities = @filtered_activities.order(:start_date).to_a

    (0..5).each do |rest_days|
      activities_with_x_rest_days = activities.select.with_index do |activity, index|
        next false if index == 0
        
        previous_activity = activities[index - 1]
        
        # Convert to dates
        current_date = activity.start_date.to_date
        previous_date = previous_activity.start_date.to_date
        
        # Calculate calendar days between
        calendar_days_between = (current_date - previous_date).to_i
        
        if rest_days == 5
          calendar_days_between >= 6
        else
          calendar_days_between == rest_days + 1
        end
      end
      
      avg_pace = if activities_with_x_rest_days.empty?
                  0
                else
                  activities_with_x_rest_days.sum do |activity|
                    next 0 if activity.duration.nil? || activity.distance.nil? || activity.distance == 0
                    activity.duration.to_f / (activity.distance / 1000.0) / 60.0
                  end.to_f / activities_with_x_rest_days.size
                end
      
      key = rest_days == 5 ? "5+" : rest_days
      
      results[key] = {
        count: activities_with_x_rest_days.count,
        pace: avg_pace
      }
    end
    results
  end

  def calculate_pace_consistency
    splits_data = @filtered_splits.joins(:activity)
                      .group(:split)
                      .average("splits.elapsed_time::float / (splits.distance / 1000.0) / 60.0")
    
    return "Not enough split data available" if splits_data.size < 2
    
    sorted_splits = splits_data.sort.to_h
    first_km_pace = sorted_splits.values.first
    last_km_pace = sorted_splits.values.last
    km_count = sorted_splits.size
    
    average_pace_change_per_km = (last_km_pace - first_km_pace) / (km_count - 1)
    
    { 
      average_pace_change_per_km: average_pace_change_per_km,
      splits_data: sorted_splits,
      analysis_type: "distance_vs_pace"
    }
  end

  def calculate_within_run_pace_consistency
    activities_with_splits = @filtered_activities.joins(:splits).includes(:splits)
    
    pace_trends = []
    
    activities_with_splits.each do |activity|
      splits = activity.splits.order(:split)
      next if splits.size < 3
      
      split_paces = splits.map do |split|
        split.elapsed_time / 60.0 / (split.distance / 1000.0)  # min/km
      end
      
      n = split_paces.size
      x_values = (1..n).to_a  # km 1, 2, 3, etc.
      
      x_avg = x_values.sum.to_f / n
      y_avg = split_paces.sum / n
      
      numerator = x_values.zip(split_paces).sum { |x, y| (x - x_avg) * (y - y_avg) }
      denominator = x_values.sum { |x| (x - x_avg) ** 2 }
      
      slope = denominator != 0 ? numerator / denominator : 0
      pace_trends << slope
    end
    
    return "Not enough data for within-run analysis" if pace_trends.empty?
    
    avg_trend = pace_trends.sum / pace_trends.size
    
    {
      average_pace_trend_per_km: avg_trend,
      interpretation: interpret_pace_trend(avg_trend),
      runs_analyzed: pace_trends.size
    }
  end

  def interpret_pace_trend(slope)
    if slope > 0.1
      "You tend to start too fast and slow down significantly"
    elsif slope > 0.02
      "You tend to slow down slightly during runs"
    elsif slope > -0.02
      "You maintain very consistent pace throughout runs"
    elsif slope > -0.1
      "You tend to speed up slightly during runs"
    else
      "You tend to start conservatively and finish strong"
    end
  end
end