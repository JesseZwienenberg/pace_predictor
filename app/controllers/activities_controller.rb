class ActivitiesController < ApplicationController
  def index
    @activities = Activity.includes(:splits, :best_efforts).order(start_date: :desc)
    @total_distance = Activity.sum(:distance) / 1000.0
    @total_time = Activity.sum(:duration)
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
end