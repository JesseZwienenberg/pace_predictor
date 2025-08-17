class DashboardController < ApplicationController
  def index
    @activities = Activity.order(start_date: :desc)
  
    @total_distance = Activity.sum(:distance) / 1000.0
    @total_time = Activity.sum(:duration)
    @total_runs = @activities.count

    activities_without_intervals = @activities.where("name NOT ILIKE ? AND name NOT ILIKE ?", "%interval%", "%herstel%")
    @avg_pace = activities_without_intervals.any? ? activities_without_intervals.average("duration::float / (distance / 1000.0) / 60.0") : 0
  end
end