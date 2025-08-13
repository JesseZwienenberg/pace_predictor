module TimeFormattable
  extend ActiveSupport::Concern
  
  def time_formatted(time_in_seconds)
    minutes = (time_in_seconds / 60).to_i
    seconds = (time_in_seconds % 60).to_i
    "#{minutes}m #{seconds}s"
  end
end