class ActivitiesController < ApplicationController
  include ApplicationHelper

  def index
    sort_column = params[:sort] || 'start_date'
    sort_direction = params[:direction] || 'desc'
    sortable_columns = {
      'date' => 'start_date',
      'name' => 'name',
      'distance' => 'distance',
      'duration' => 'duration',
      'pace_per_km' => 'average_speed',
      'pace_kmph' => 'average_speed',
      'elevation' => 'elevation_gain'
    }
  
    column = sortable_columns[sort_column] || 'start_date'
    @activities = Activity.includes(:splits, :best_efforts).order("#{column} #{sort_direction}")
    
    # Apply filters based on parameters
    @activities = apply_filters(@activities)
    
    @total_distance = apply_filters(Activity).sum(:distance) / 1000.0
    @total_time = apply_filters(Activity).sum(:duration)
    @filter_description = build_filter_description
  end

  def show
    @activity = Activity.find(params[:id])
    @split_data = prepare_split_data if @activity.splits.any?

    set_graph_signals
  end

  def import
    if session[:strava_access_token]
      begin
        import_strava_activities
        redirect_to activities_path, notice: "Activities imported successfully!"
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, SocketError
        redirect_to root_path, alert: "Unable to connect to Strava. Please try again later."
      end
    else
      redirect_to dashboard_path, alert: "Please connect to Strava first"
    end
  end

  def import_speed
    @activity = Activity.find(params[:id])
    
    if session[:strava_access_token]
      if import_activity_speed_stream(@activity.strava_id, session[:strava_access_token])
        redirect_to @activity, notice: "Speed data imported successfully!"
      else
        redirect_to @activity, alert: "Failed to import speed data"
      end
    else
      redirect_to dashboard_path, alert: "Please connect to Strava first"
    end
  end  

  private

  def import_activity_speed_stream(strava_id, access_token)
    # Request streams for velocity (speed) data
    response = HTTParty.get(
      "https://www.strava.com/api/v3/activities/#{strava_id}/streams",
      headers: { 'Authorization' => "Bearer #{access_token}" },
      query: { 
        keys: 'velocity_smooth,time,distance',
        key_by_type: true 
      }
    )
    
    return false unless response.success?

    streams_data = response.parsed_response
    return false unless streams_data['velocity_smooth']
    
    # Parse and save the speed data
    speed_data = {
      speeds_mps: streams_data['velocity_smooth']['data'],
      times: streams_data['time'] ? streams_data['time']['data'] : nil,
      distances: streams_data['distance'] ? streams_data['distance']['data'] : nil
    }
    
    # Convert to other units for convenience
    speed_data[:speeds_kmh] = speed_data[:speeds_mps].map { |speed| speed * 3.6 }
    speed_data[:paces_min_per_km] = speed_data[:speeds_mps].map do |speed|
      speed > 0 ? (1000.0 / speed / 60.0) : 0
    end

    # Compute best efforts
    best_efforts = find_min_consecutive_for_multiples_of_10(speed_data[:speeds_mps])
    
    # Save to database
    activity = Activity.find_by(strava_id: strava_id)
    activity&.update(
      speed_stream: speed_data,
      all_best_efforts: best_efforts
    )
    
    true
  rescue => e
    false
  end

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
          begin
            import_detailed_activity(activity_data['id'], access_token)
          rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, SocketError
            # Skip this activity and continue with the next one
            next
          end
        end
      end
    end
  end

  def import_detailed_activity(strava_id, access_token)
    # Skip if activity already exists
    return if Activity.find_by(strava_id:strava_id)

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

  def apply_filters(activities)
    if params[:day_of_week].present?
      day_name = params[:day_of_week].capitalize
      dow_number = Date::DAYNAMES.index(day_name)
      activities = activities.where("EXTRACT(dow FROM start_date) = ?", dow_number) if dow_number
    end
    
    if params[:time_window].present?
      hours = time_window_to_hours(params[:time_window])
      activities = activities.where("EXTRACT(hour FROM (start_date AT TIME ZONE 'UTC' AT TIME ZONE 'Europe/Amsterdam')) IN (?)", hours) if hours
    end
    
    if params[:weekend] == 'true'
      activities = activities.where("EXTRACT(dow FROM start_date) IN (0, 6)")
    elsif params[:weekday] == 'true'
      activities = activities.where("EXTRACT(dow FROM start_date) BETWEEN 1 AND 5")
    end
    
    if params[:month].present?
      begin
        month_name, year = params[:month].split(' ')
        month_number = Date::MONTHNAMES.index(month_name)
        if month_number && year
          activities = activities.where("EXTRACT(month FROM start_date) = ? AND EXTRACT(year FROM start_date) = ?", month_number, year.to_i)
        end
        rescue
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

  def prepare_split_data
    splits = @activity.splits.order(:split)
    
    # Calculate average pace
    total_time = splits.sum(:elapsed_time)
    total_distance = splits.sum(:distance)
    average_pace = total_distance > 0 ? (total_time / 60.0) / (total_distance / 1000.0) : 0
    
    # Process each split
    splits.map do |split|
      pace = split.distance > 0 ? (split.elapsed_time / 60.0) / (split.distance / 1000.0) : 0
      pace_difference = pace - average_pace
      pace_difference_seconds = pace_difference * 60
      
      {
        split: split,
        pace: pace,
        km_label: split.distance > 990 ? split.split.to_s : sprintf('%.2f', split.split - 1 + split.distance / 1000),
        formatted_pace: format_pace(pace),
        speed_kmph: pace_to_kmph(pace),
        elevation_text: "#{split.elevation_difference.round(0)}m",
        difference_data: calculate_difference_display(split, pace_difference, pace_difference_seconds)
      }
    end
  end

  def calculate_difference_display(split, pace_difference, pace_difference_seconds)
    rounded_difference = sprintf('%.2f', pace_difference.abs).to_f
    is_faster = pace_difference < 0
    
    if split.distance < 800 || rounded_difference == 0.0
      {
        color: 'inherit',
        text: split.distance < 800 ? '' : format_time(pace_difference_seconds.abs)
      }
    elsif pace_difference_seconds.abs < 10
      {
        color: is_faster ? 'mediumseagreen' : 'indianred',
        text: "#{is_faster ? '' : '+'}#{format_time(pace_difference_seconds.abs)}"
      }
    else
      {
        color: is_faster ? 'green' : 'red',
        text: "#{is_faster ? '' : '+'}#{format_time(pace_difference_seconds.abs)}"
      }
    end
  end

  def find_min_consecutive_for_multiples_of_10(speeds)
    total_sum = speeds.sum
    max_target = (total_sum / 10).floor * 10

    return [] if max_target == 0
    
    results = []

    index = 0
    
    (10..max_target).step(10) do |target|
      index += 1
      min_length = Float::INFINITY
      current_sum = 0
      left = 0
      
      speeds.each_with_index do |speed, right|
        current_sum += speed
        
        while current_sum >= target
          min_length = [min_length, right - left + 1].min
          current_sum -= speeds[left]
          left += 1
        end
      end
      
      results << min_length * 100.0 / index / 60
    end

    results
  end

  def set_graph_signals
    if @activity.speed_stream
      speeds = @activity.speed_stream["speeds_mps"]
      @speed_chart_datasets = [{
        label: 'Pace',
        data: speeds.each_with_index.filter_map do |speed, index|
          next if speed == 0
          {
            x: index, # seconds
            y: (1000.0 / 60.0) / speed # Pace in min/km
          }
        end,
        color: '#09954f',
        showPoints: false,
        borderWidth: 3
      }]
    end

    if @activity.all_best_efforts
      speeds = @activity.all_best_efforts
      @best_efforts_datasets = [{
        label: 'Pace',
        data: speeds.each_with_index.filter_map do |speed, index|
          next if speed == 0
          {
            x: (index * 0.01).round(2), # Distance in km
            y: speed # Pace in min/km
          }
        end,
        color: '#09954f',
        showPoints: false,
        borderWidth: 3
      }] 
    end
  end
end