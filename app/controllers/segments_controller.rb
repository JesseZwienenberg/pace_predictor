# app/controllers/segments_controller.rb
class SegmentsController < ApplicationController
  def search
    # Just shows the search form
  end
  
  def easy_targets
    finder = EasySegmentFinder.new(session[:strava_access_token])
    
    @segments = finder.find(
      params[:lat].to_f,
      params[:lng].to_f,
      params[:radius].to_f || 5,
      params[:max_distance].to_i || 3000,
      params[:max_pace].to_f
    )
    
    @max_pace = params[:max_pace]
  end
  
  def refresh_kom
    finder = EasySegmentFinder.new(session[:strava_access_token])
    kom_time = finder.refresh_segment(params[:id])
    
    redirect_back(fallback_location: root_path, notice: "KOM updated: #{kom_time}s")
  end
end