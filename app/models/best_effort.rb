class BestEffort < ApplicationRecord
  include TimeFormattable
  belongs_to :activity
  
  def formatted_time
    time_formatted(elapsed_time)
  end
end