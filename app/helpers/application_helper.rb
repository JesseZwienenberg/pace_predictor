# app/helpers/application_helper.rb
module ApplicationHelper
  def format_time(time_in_seconds)
    return "0:00" if time_in_seconds.nil? || time_in_seconds == 0
    
    minutes = (time_in_seconds / 60).to_i
    seconds = (time_in_seconds % 60).to_i
    "#{minutes}:#{seconds.to_s.rjust(2, '0')}"
  end
  
  def format_pace(pace_minutes_per_km)
    return "0:00" if pace_minutes_per_km.nil? || pace_minutes_per_km == 0
    
    minutes = pace_minutes_per_km.to_i
    seconds = ((pace_minutes_per_km - minutes) * 60).to_i
    "#{minutes}:#{seconds.to_s.rjust(2, '0')}"
  end
  
  def format_total_time(time_in_seconds)
    return "0h 0m 0s" if time_in_seconds.nil? || time_in_seconds == 0
    
    hours = (time_in_seconds / 3600).to_i
    minutes = ((time_in_seconds % 3600) / 60).to_i
    seconds = (time_in_seconds % 60).to_i
    "#{hours}h #{minutes}m #{seconds}s"
  end
end