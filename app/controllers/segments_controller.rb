# app/controllers/segments_controller.rb
class SegmentsController < ApplicationController
  def search
    # Just shows the search form
  end
  
  def easy_targets
    lat = params[:lat].to_f
    lng = params[:lng].to_f
    radius = params[:radius].to_f || 5
    max_distance = params[:max_distance].to_i || 3000
    max_pace = params[:max_pace].to_f if params[:max_pace].present?

    begin
      
      # Check if we have adequate cached coverage for this search
      # Only use cached segments if we're sorting OR if we have recent comprehensive coverage
      cached_segments_with_coords = CachedSegment.near_location(lat, lng, radius)
                                                .with_filters(max_distance_m: max_distance, max_pace_min_km: max_pace)
                                                .where('kom_time > 0')
      
      # If we're just sorting (have sort params), use cached segments to avoid API calls
      if params[:sort].present? && cached_segments_with_coords.exists?
        Rails.logger.info "🔄 Sorting request detected - using cached segments for location #{lat}, #{lng} to avoid API calls"
        
        @segments = cached_segments_with_coords.map do |seg|
          ratio = seg.difficulty_ratio
          next if !ratio || ratio <= 0
          
          distance_from_search = if seg.start_latitude && seg.start_longitude
            haversine_distance(lat, lng, seg.start_latitude.to_f, seg.start_longitude.to_f)
          else
            nil
          end
          
          {
            id: seg.strava_id,
            name: seg.name,
            distance: seg.distance,
            kom_time: seg.kom_time,
            kom_pace: seg.kom_pace,
            difficulty_ratio: ratio,
            distance_from_search: distance_from_search
          }
        end.compact
        
      elsif should_use_cached_segments?(lat, lng, radius) && cached_segments_with_coords.exists?
        Rails.logger.info "Using cached segments for location #{lat}, #{lng} radius #{radius}km (found #{cached_segments_with_coords.count})"
        
        # Convert to the format expected by the view
        @segments = cached_segments_with_coords.map do |seg|
          ratio = seg.difficulty_ratio
          next if !ratio || ratio <= 0
          
          distance_from_search = if seg.start_latitude && seg.start_longitude
            haversine_distance(lat, lng, seg.start_latitude.to_f, seg.start_longitude.to_f)
          else
            nil
          end
          
          {
            id: seg.strava_id,
            name: seg.name,
            distance: seg.distance,
            kom_time: seg.kom_time,
            kom_pace: seg.kom_pace,
            difficulty_ratio: ratio,
            distance_from_search: distance_from_search
          }
        end.compact
      else
        Rails.logger.info "No cached segments found, using API for location #{lat}, #{lng}"
        
        # Fall back to API search for new areas
        finder = EasySegmentFinder.new(session[:strava_access_token])
        
        @segments = finder.find(lat, lng, radius, max_distance, max_pace)
      end
      
      # Filter out segments that are beyond the specified radius
      @segments = @segments.select do |seg|
        if seg[:distance_from_search]
          seg[:distance_from_search] <= radius
        else
          true  # Keep segments without distance info (shouldn't happen with new searches)
        end
      end
      
      # Apply sorting
      sort_column = params[:sort] || 'ratio'
      sort_direction = params[:direction] || 'desc'
      @segments = sort_segments(@segments, sort_column, sort_direction)
      
      @max_pace = params[:max_pace]
    rescue => e
      Rails.logger.error "Error in easy_targets: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      
      if e.message.include?("Rate limited")
        @error = "Rate limit exceeded! Please wait to search again."
        @rate_limited = true
        
        # Still show cached segments if available, even when rate limited
        Rails.logger.info "Rate limited - checking for cached segments in area"
        cached_segments_with_coords = CachedSegment.near_location(lat, lng, radius)
                                                  .with_filters(max_distance_m: max_distance, max_pace_min_km: max_pace)
                                                  .where('kom_time > 0')
        
        if cached_segments_with_coords.exists?
          Rails.logger.info "Found #{cached_segments_with_coords.count} cached segments despite rate limiting"
          
          @segments = cached_segments_with_coords.map do |seg|
            ratio = seg.difficulty_ratio
            next if !ratio || ratio <= 0
            
            distance_from_search = if seg.start_latitude && seg.start_longitude
              haversine_distance(lat, lng, seg.start_latitude.to_f, seg.start_longitude.to_f)
            else
              nil
            end
            
            {
              id: seg.strava_id,
              name: seg.name,
              distance: seg.distance,
              kom_time: seg.kom_time,
              kom_pace: seg.kom_pace,
              difficulty_ratio: ratio,
              distance_from_search: distance_from_search
            }
          end.compact
          
          # Filter out segments that are beyond the specified radius
          @segments = @segments.select do |seg|
            if seg[:distance_from_search]
              seg[:distance_from_search] <= radius
            else
              true
            end
          end
          
          # Apply sorting
          sort_column = params[:sort] || 'ratio'
          sort_direction = params[:direction] || 'desc'
          @segments = sort_segments(@segments, sort_column, sort_direction)
        else
          @segments = []
        end
      else
        @error = "An error occurred while searching for segments. Showing cached segments if available."
        
        # Still check database for cached segments even on API failures
        Rails.logger.info "API failed - checking for cached segments in area"
        cached_segments_with_coords = CachedSegment.near_location(lat, lng, radius)
                                                  .with_filters(max_distance_m: max_distance, max_pace_min_km: max_pace)
                                                  .where('kom_time > 0')
        
        if cached_segments_with_coords.exists?
          Rails.logger.info "Found #{cached_segments_with_coords.count} cached segments despite API failure"
          
          @segments = cached_segments_with_coords.map do |seg|
            ratio = seg.difficulty_ratio
            next if !ratio || ratio <= 0
            
            distance_from_search = if seg.start_latitude && seg.start_longitude
              haversine_distance(lat, lng, seg.start_latitude.to_f, seg.start_longitude.to_f)
            else
              nil
            end
            
            {
              id: seg.strava_id,
              name: seg.name,
              distance: seg.distance,
              kom_time: seg.kom_time,
              kom_pace: seg.kom_pace,
              difficulty_ratio: ratio,
              distance_from_search: distance_from_search
            }
          end.compact
          
          # Filter out segments that are beyond the specified radius
          @segments = @segments.select do |seg|
            if seg[:distance_from_search]
              seg[:distance_from_search] <= radius
            else
              true
            end
          end
          
          # Apply sorting
          sort_column = params[:sort] || 'ratio'
          sort_direction = params[:direction] || 'desc'
          @segments = sort_segments(@segments, sort_column, sort_direction)
        else
          @segments = []
        end
      end
      
      @max_pace = params[:max_pace]
    end
  end
  
  def refresh_kom
    finder = EasySegmentFinder.new(session[:strava_access_token])
    kom_time = finder.refresh_segment(params[:id])
    
    redirect_back(fallback_location: root_path, notice: "KOM updated: #{kom_time}s")
  end

  private

  def should_use_cached_segments?(lat, lng, radius)
    # For now, be conservative and always use API for new searches
    # This ensures we get comprehensive coverage for each search
    # Only sorting operations will use cached segments
    false
  end

  def haversine_distance(lat1, lng1, lat2, lng2)
    # Calculate distance between two points using Haversine formula
    r = 6371 # Earth's radius in kilometers
    
    lat1_rad = lat1 * Math::PI / 180
    lat2_rad = lat2 * Math::PI / 180
    delta_lat = (lat2 - lat1) * Math::PI / 180
    delta_lng = (lng2 - lng1) * Math::PI / 180
    
    a = Math.sin(delta_lat / 2) * Math.sin(delta_lat / 2) +
        Math.cos(lat1_rad) * Math.cos(lat2_rad) *
        Math.sin(delta_lng / 2) * Math.sin(delta_lng / 2)
    
    c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
    
    r * c
  end

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
    when 'distance_from_search'
      # Handle segments without distance_from_search (put them last)
      segments.sort_by { |seg| seg[:distance_from_search] || Float::INFINITY }
    else
      segments.sort_by { |seg| seg[:name].downcase }
    end

    sort_direction == 'desc' ? sorted.reverse : sorted
  end
end