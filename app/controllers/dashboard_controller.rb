class DashboardController < ApplicationController
  def index
    @activities = Activity.order(start_date: :desc)
    @total_distance = Activity.sum(:distance) / 1000.0  # Convert to km
    @total_time = Activity.sum(:duration)  # In seconds
    @avg_pace = @activities.any? ? @activities.average("duration::float / (distance / 1000.0) / 60.0") : 0
  end
end