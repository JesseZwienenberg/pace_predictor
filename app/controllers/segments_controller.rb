# app/controllers/segments_controller.rb
class SegmentsController < ApplicationController
  def search
    # Just shows the search form
  end
  
  def easy_targets
    begin
      finder = EasySegmentFinder.new(session[:strava_access_token])
      
      @segments = finder.find(
        params[:lat].to_f,
        params[:lng].to_f,
        params[:radius].to_f || 5,
        params[:max_distance].to_i || 3000,
        params[:max_pace].to_f
      )
      
      # Apply sorting
      sort_column = params[:sort] || 'name'
      sort_direction = params[:direction] || 'asc'
      @segments = sort_segments(@segments, sort_column, sort_direction)
      
      @max_pace = params[:max_pace]
    rescue => e
      Rails.logger.error "Error in easy_targets: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      @segments = []
      
      if e.message.include?("Rate limited")
        @error = "Rate limit exceeded! You've used your daily API quota. Please wait until tomorrow to search again."
        @rate_limited = true
      else
        @error = "An error occurred while searching for segments. Please try again."
      end
    end
  end
  
  def refresh_kom
    finder = EasySegmentFinder.new(session[:strava_access_token])
    kom_time = finder.refresh_segment(params[:id])
    
    redirect_back(fallback_location: root_path, notice: "KOM updated: #{kom_time}s")
  end

  private

  def sort_segments(segments, sort_column, sort_direction)
    sorted = case sort_column
    when 'name'
      segments.sort_by { |seg| seg[:name].downcase }
    when 'distance'
      segments.sort_by { |seg| seg[:distance] }
    when 'kom_pace'
      segments.sort_by { |seg| seg[:kom_pace] }
    when 'ratio'
      segments.sort_by { |seg| seg[:difficulty_ratio] }
    else
      segments.sort_by { |seg| seg[:name].downcase }
    end

    sort_direction == 'desc' ? sorted.reverse : sorted
  end
end