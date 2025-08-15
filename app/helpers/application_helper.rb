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

  def pace_to_kmph(pace_minutes_per_km)
    return 0 if pace_minutes_per_km.nil? || pace_minutes_per_km == 0
    
    pace_seconds_per_km = pace_minutes_per_km * 60
    kmph = 3600.0 / pace_seconds_per_km
    kmph.round(2)
  end

  def grey_decimals(distance, decimals: 2)
    distance = 0 if distance.nil?

    distance_rounded = distance.round(2)
    whole_km = distance_rounded.to_i
    decimal_part = (distance_rounded % 1).round(2)
    
    decimal_str = sprintf("%.#{decimals}f", decimal_part)[1..-1]
    result = "#{whole_km}<span style='color: grey;'>#{decimal_str}</span>"
    result.html_safe

  end
end