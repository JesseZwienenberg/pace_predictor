# app/controllers/segments_controller.rb
class SegmentsController < ApplicationController
  def search
    # Just shows the search form
  end
  
  def easy_targets
    # Handle database-only filter searches (from search page buttons)
    if params[:filter].present?
      handle_database_filter_search(params[:filter])
      return
    end

    lat = params[:lat].to_f
    lng = params[:lng].to_f
    radius = params[:radius].to_f || 5
    max_distance = params[:max_distance].to_i || 3000
    max_pace = params[:max_pace].to_f if params[:max_pace].present?
    show_done_only = params[:show_done_only] == "true"
    show_favorited_only = params[:show_favorited_only] == "true"

    begin
      
      # Check if we have adequate cached coverage for this search
      # Only use cached segments if we're sorting OR if we have recent comprehensive coverage
      cached_segments_with_coords = CachedSegment.near_location(lat, lng, radius)
                                                .with_filters(max_distance_m: max_distance, max_pace_min_km: max_pace, show_done_only: show_done_only, show_favorited_only: show_favorited_only)
                                                .where('kom_time > 0')
      
      # If we're just sorting (have sort params) or filtering by markings, use cached segments to avoid API calls
      if (params[:sort].present? && cached_segments_with_coords.exists?) || show_done_only || show_favorited_only
        reason = if show_done_only || show_favorited_only
          "marking filter detected - only cached segments can have markings"
        else
          "sorting request detected"
        end
        Rails.logger.info "🔄 #{reason.capitalize} - using cached segments for location #{lat}, #{lng} to avoid API calls"
        
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
            distance_from_search: distance_from_search,
            background_color_class: seg.background_color_class,
            is_done: seg.is_done,
            is_favorited: seg.is_favorited,
            is_unavailable: seg.is_unavailable
          }
        end.compact
        
      elsif show_done_only || show_favorited_only
        # When filtering by markings, only use cached segments (no API calls needed)
        Rails.logger.info "Marking filter active - using only cached segments for location #{lat}, #{lng} (found #{cached_segments_with_coords.count})"
        
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
            distance_from_search: distance_from_search,
            background_color_class: seg.background_color_class,
            is_done: seg.is_done,
            is_favorited: seg.is_favorited,
            is_unavailable: seg.is_unavailable
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
            distance_from_search: distance_from_search,
            background_color_class: seg.background_color_class,
            is_done: seg.is_done,
            is_favorited: seg.is_favorited,
            is_unavailable: seg.is_unavailable
          }
        end.compact
      else
        Rails.logger.info "No cached segments found, using API for location #{lat}, #{lng}"
        
        # Fall back to API search for new areas
        finder = EasySegmentFinder.new(session[:strava_access_token])
        
        api_segments = finder.find(lat, lng, radius, max_distance, max_pace)
        
        # Enhance API segments with cached marking information if available
        @segments = api_segments.map do |seg|
          cached_seg = CachedSegment.find_by(strava_id: seg[:id])
          if cached_seg
            seg.merge({
              background_color_class: cached_seg.background_color_class,
              is_done: cached_seg.is_done,
              is_favorited: cached_seg.is_favorited,
              is_unavailable: cached_seg.is_unavailable
            })
          else
            seg.merge({
              background_color_class: '',
              is_done: false,
              is_favorited: false,
              is_unavailable: false
            })
          end
        end
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
                                                  .with_filters(max_distance_m: max_distance, max_pace_min_km: max_pace, show_done_only: show_done_only, show_favorited_only: show_favorited_only)
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
              distance_from_search: distance_from_search,
              background_color_class: seg.background_color_class,
              is_done: seg.is_done,
              is_favorited: seg.is_favorited,
              is_unavailable: seg.is_unavailable
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
                                                  .with_filters(max_distance_m: max_distance, max_pace_min_km: max_pace, show_done_only: show_done_only, show_favorited_only: show_favorited_only)
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
              distance_from_search: distance_from_search,
              background_color_class: seg.background_color_class,
              is_done: seg.is_done,
              is_favorited: seg.is_favorited,
              is_unavailable: seg.is_unavailable
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
    
    # Get updated segment data for response
    cached_segment = CachedSegment.find_by(strava_id: params[:id])
    kom_pace = nil
    difficulty_ratio = nil
    
    if cached_segment && cached_segment.kom_time && cached_segment.distance
      # Calculate KOM pace (min/km)
      kom_pace = (cached_segment.kom_time / 60.0) / (cached_segment.distance / 1000.0)
      difficulty_ratio = cached_segment.difficulty_ratio
    end
    
    respond_to do |format|
      format.html { redirect_back(fallback_location: root_path, notice: "KOM updated: #{kom_time}s") }
      format.json { render json: { success: true, segment_id: params[:id], kom_time: kom_time, kom_pace: kom_pace, difficulty_ratio: difficulty_ratio } }
    end
  rescue => e
    respond_to do |format|
      format.html { redirect_back(fallback_location: root_path, alert: "Failed to refresh KOM: #{e.message}") }
      format.json { render json: { success: false, error: e.message }, status: 500 }
    end
  end

  def mark_done
    segment = CachedSegment.find_by(strava_id: params[:id])
    if segment
      segment.update!(is_done: !segment.is_done, is_favorited: false, is_unavailable: false)
      status = segment.is_done ? "done" : "unmarked"
      
      respond_to do |format|
        format.html { redirect_back(fallback_location: root_path, notice: "Segment marked as #{status}") }
        format.json { render json: { success: true, status: status, segment_id: params[:id], background_class: segment.background_color_class } }
      end
    else
      respond_to do |format|
        format.html { redirect_back(fallback_location: root_path, alert: "Segment not found") }
        format.json { render json: { success: false, error: "Segment not found" }, status: 404 }
      end
    end
  end

  def mark_favorited
    segment = CachedSegment.find_by(strava_id: params[:id])
    if segment
      segment.update!(is_favorited: !segment.is_favorited, is_done: false, is_unavailable: false)
      status = segment.is_favorited ? "favorited" : "unmarked"
      
      respond_to do |format|
        format.html { redirect_back(fallback_location: root_path, notice: "Segment marked as #{status}") }
        format.json { render json: { success: true, status: status, segment_id: params[:id], background_class: segment.background_color_class } }
      end
    else
      respond_to do |format|
        format.html { redirect_back(fallback_location: root_path, alert: "Segment not found") }
        format.json { render json: { success: false, error: "Segment not found" }, status: 404 }
      end
    end
  end

  def mark_unavailable
    segment = CachedSegment.find_by(strava_id: params[:id])
    if segment
      segment.update!(is_unavailable: !segment.is_unavailable, is_done: false, is_favorited: false)
      status = segment.is_unavailable ? "unavailable" : "unmarked"
      
      respond_to do |format|
        format.html { redirect_back(fallback_location: root_path, notice: "Segment marked as #{status}") }
        format.json { render json: { success: true, status: status, segment_id: params[:id], background_class: segment.background_color_class } }
      end
    else
      respond_to do |format|
        format.html { redirect_back(fallback_location: root_path, alert: "Segment not found") }
        format.json { render json: { success: false, error: "Segment not found" }, status: 404 }
      end
    end
  end

  private

  def handle_database_filter_search(filter)
    segments = case filter
    when 'done'
      CachedSegment.where(is_done: true).order(:name)
    when 'favorited'
      CachedSegment.where(is_favorited: true).order(:name)
    else
      CachedSegment.none
    end
    
    # Get user location if provided
    user_lat = params[:lat].to_f if params[:lat].present?
    user_lng = params[:lng].to_f if params[:lng].present?
    
    # Format segments similar to the normal search results
    @segments = segments.map do |seg|
      ratio = seg.difficulty_ratio
      next if !ratio || ratio <= 0
      
      # Calculate distance from user location if available
      distance_from_search = nil
      if user_lat && user_lng && seg.start_latitude && seg.start_longitude
        distance_from_search = haversine_distance(user_lat, user_lng, seg.start_latitude.to_f, seg.start_longitude.to_f)
      end
      
      {
        id: seg.strava_id,
        name: seg.name,
        distance: seg.distance,
        kom_time: seg.kom_time,
        kom_pace: seg.kom_pace,
        difficulty_ratio: ratio,
        distance_from_search: distance_from_search,
        is_done: seg.is_done,
        is_favorited: seg.is_favorited,
        is_unavailable: seg.is_unavailable,
        background_color_class: seg.background_color_class
      }
    end.compact
    
    # Apply sorting (same as regular search)
    sort_column = params[:sort] || 'ratio'
    sort_direction = params[:direction] || 'desc'
    @segments = sort_segments(@segments, sort_column, sort_direction)
    
    location_info = user_lat && user_lng ? "with user location (#{user_lat}, #{user_lng})" : "without location"
    Rails.logger.info "🗂️  Database filter search: #{filter} #{location_info} - found #{@segments.length} segments (sorted by #{sort_column} #{sort_direction})"
  end

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