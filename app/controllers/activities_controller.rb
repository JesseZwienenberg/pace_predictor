class ActivitiesController < ApplicationController
  def index
    @activities = Activity.includes(:splits, :best_efforts).order(start_date: :desc)
    
    # Apply filters based on parameters
    @activities = apply_filters(@activities)
    
    @total_distance = apply_filters(Activity).sum(:distance) / 1000.0
    @total_time = apply_filters(Activity).sum(:duration)
    @filter_description = build_filter_description
  end

  def show
    @activity = Activity.find(params[:id])
  end

  def import
    if session[:strava_access_token]
      import_strava_activities
      redirect_to activities_path, notice: "Activities imported successfully!"
    else
      redirect_to dashboard_path, alert: "Please connect to Strava first"
    end
  end

  private

  def import_strava_activities
    access_token = session[:strava_access_token]
    
    # Get activities from Strava API
    response = HTTParty.get(
      "https://www.strava.com/api/v3/athlete/activities",
      headers: { 'Authorization' => "Bearer #{access_token}" },
      query: { per_page: 200 }
    )
    
    if response.success?
      response.each do |activity_data|
        # Only import running activities
        if activity_data['type'] == 'Run'
          import_detailed_activity(activity_data['id'], access_token)
        end
      end
    end
  end

  def import_detailed_activity(strava_id, access_token)
    # Get detailed activity data
    detailed_response = HTTParty.get(
      "https://www.strava.com/api/v3/activities/#{strava_id}",
      headers: { 'Authorization' => "Bearer #{access_token}" }
    )
    
    return unless detailed_response.success?

    data = detailed_response

    # Create or update activity
    activity = Activity.find_or_create_by(strava_id: strava_id) do |a|
      a.name = data['name']
      a.distance = data['distance']
      a.duration = data['moving_time']
      a.start_date = DateTime.parse(data['start_date'])
      a.average_heartrate = data['average_heartrate']
      a.elevation_gain = data['total_elevation_gain']
      a.average_speed = data['average_speed']
      a.max_speed = data['max_speed']
      a.elapsed_time = data['elapsed_time']
      a.activity_type = data['type']
    end

    # Import splits
    if data['splits_metric']&.any?
      activity.splits.destroy_all  # Clear existing splits
      data['splits_metric'].each_with_index do |split_data, index|
        activity.splits.create!(
          distance: split_data['distance'],
          elapsed_time: split_data['elapsed_time'],
          elevation_difference: split_data['elevation_difference'],
          moving_time: split_data['moving_time'],
          split: index + 1
        )
      end
    end

    # Import best efforts
    if data['best_efforts']&.any?
      activity.best_efforts.destroy_all  # Clear existing best efforts
      data['best_efforts'].each do |effort_data|
        activity.best_efforts.create!(
          name: effort_data['name'],
          elapsed_time: effort_data['elapsed_time'],
          moving_time: effort_data['moving_time'],
          distance: effort_data['distance'],
          start_index: effort_data['start_index'],
          end_index: effort_data['end_index']
        )
      end
    end
  end

  private

  def apply_filters(activities)
    if params[:day_of_week].present?
      day_name = params[:day_of_week].capitalize
      dow_number = Date::DAYNAMES.index(day_name)
      activities = activities.where("EXTRACT(dow FROM start_date) = ?", dow_number) if dow_number
    end
    
    if params[:time_window].present?
      hours = time_window_to_hours(params[:time_window])
      activities = activities.where("EXTRACT(hour FROM start_date) IN (?)", hours) if hours
    end
    
    if params[:weekend] == 'true'
      activities = activities.where("EXTRACT(dow FROM start_date) IN (0, 6)")
    elsif params[:weekday] == 'true'
      activities = activities.where("EXTRACT(dow FROM start_date) BETWEEN 1 AND 5")
    end
    
    if params[:month].present?
      # Convert "January 2024" format back to filtering
      begin
        month_name, year = params[:month].split(' ')
        month_number = Date::MONTHNAMES.index(month_name)
        if month_number && year
          activities = activities.where("EXTRACT(month FROM start_date) = ? AND EXTRACT(year FROM start_date) = ?", month_number, year.to_i)
        end
      rescue
        # If parsing fails, ignore the filter
      end
    end
    
    activities
  end

  def time_window_to_hours(window)
    case window
    when "00:00-04:00" then [0, 1, 2, 3]
    when "04:00-08:00" then [4, 5, 6, 7]
    when "08:00-12:00" then [8, 9, 10, 11]
    when "12:00-16:00" then [12, 13, 14, 15]
    when "16:00-20:00" then [16, 17, 18, 19]
    when "20:00-24:00" then [20, 21, 22, 23]
    else nil
    end
  end

  def build_filter_description
    filters = []
    
    filters << "#{params[:day_of_week].capitalize} runs" if params[:day_of_week].present?
    filters << "#{params[:time_window]} runs" if params[:time_window].present?
    filters << "Weekend runs" if params[:weekend] == 'true'
    filters << "Weekday runs" if params[:weekday] == 'true'
    filters << "#{params[:month]} runs" if params[:month].present?
    
    filters.any? ? "Showing: #{filters.join(', ')}" : nil
  end
end