# app/services/easy_segment_finder.rb
class EasySegmentFinder
  def initialize(access_token)
    @client = Strava::Api::Client.new(access_token: access_token)
    @access_token = access_token
    @rate_limited = false
    @last_request_time = Time.current
    @request_delay = 0.5  # Start with 500ms delay between requests
  end
  
  def find(lat, lng, max_radius_km, max_segment_distance_m = 5000, max_pace_min_km = nil)
    all_segments = fetch_segments_in_grid(lat, lng, max_radius_km)
    
    # Check if we got rate limited during segment fetching
    if @rate_limited
      raise "Rate limited! Daily limit exceeded. Please wait until tomorrow to search again."
    end
    
    Rails.logger.info "Found #{all_segments.count} total segments to check"
    
    results = []
    processed_count = 0
    
    all_segments.each do |seg|
      # Break early if we hit network issues (likely rate limiting)
      if @rate_limited
        Rails.logger.warn "🛑 Stopping segment processing due to rate limiting. Processed #{processed_count}/#{all_segments.count} segments."
        break
      end
      
      next if seg.distance > max_segment_distance_m
      
      processed_count += 1
      
      # Check cache first
      cached = CachedSegment.find_by(strava_id: seg.id)
      
      if cached
        kom_time = cached.kom_time
        Rails.logger.info "Using cached KOM for #{seg.name}: #{kom_time}s"
      else
        # Fetch from API and cache it
        kom_time = fetch_kom_time_from_leaderboard(seg.id, seg.name)
        
        # If we got rate limited during the fetch, break immediately
        if @rate_limited
          Rails.logger.warn "🛑 Stopping segment processing due to network issues (likely rate limiting). Processed #{processed_count}/#{all_segments.count} segments."
          break
        end
        
        if kom_time && kom_time > 0
          CachedSegment.create!(
            strava_id: seg.id,
            name: seg.name,
            distance: seg.distance,
            kom_time: kom_time,
            start_latitude: seg.start_latlng&.first,
            start_longitude: seg.start_latlng&.last
          )
          Rails.logger.info "Cached new segment: #{seg.name}"
        end
      end
      
      next if !kom_time || kom_time == 0
      
      kom_pace = (kom_time / 60.0) / (seg.distance / 1000.0)
      
      next if kom_pace < 1.0  # Sanity check
      next if max_pace_min_km && kom_pace < max_pace_min_km
      
      ratio = ::SegmentAnalyzer.difficulty_ratio(seg.distance, kom_time)
      next if !ratio
      
      results << {
        id: seg.id,
        name: seg.name,
        distance: seg.distance,
        kom_time: kom_time,
        kom_pace: kom_pace,
        difficulty_ratio: ratio
      }
    end
    
    Rails.logger.info "Returning #{results.count} segments after filtering (processed #{processed_count}/#{all_segments.count} total segments)"
    results.sort_by { |s| -s[:difficulty_ratio] }
  end
  
  # Add method to refresh a single segment
  def refresh_segment(segment_id)
    kom_time = fetch_kom_time_from_leaderboard(segment_id, "Refresh")
    
    if kom_time && kom_time > 0
      cached = CachedSegment.find_by(strava_id: segment_id)
      if cached
        cached.update!(kom_time: kom_time)
      else
        # Fetch full segment details if not cached
        seg = @client.segment(segment_id)
        CachedSegment.create!(
          strava_id: segment_id,
          name: seg.name,
          distance: seg.distance,
          kom_time: kom_time,
          start_latitude: seg.start_latlng&.first,
          start_longitude: seg.start_latlng&.last
        )
      end
    end
    
    kom_time
  end
  
  private
  
  def fetch_segments_in_grid(center_lat, center_lng, radius_km)
    segments = {}
    cell_size_km = 2.0
    num_cells = (radius_km / cell_size_km).ceil
    total_cells = (2 * num_cells + 1) ** 2
    processed_cells = 0
    
    (-num_cells..num_cells).each do |lat_offset|
      (-num_cells..num_cells).each do |lng_offset|
        # Break early if we hit rate limits
        if @rate_limited
          Rails.logger.warn "🛑 Stopping grid search due to rate limiting. Processed #{processed_cells}/#{total_cells} cells."
          break
        end
        
        lat_shift = lat_offset * cell_size_km / 111.0
        lng_shift = lng_offset * cell_size_km / (111.0 * Math.cos(center_lat * Math::PI / 180))
        
        cell_lat = center_lat + lat_shift
        cell_lng = center_lng + lng_shift
        
        distance_from_center = Math.sqrt((lat_shift * 111)**2 + (lng_shift * 111 * Math.cos(center_lat * Math::PI / 180))**2)
        next if distance_from_center > radius_km
        
        processed_cells += 1
        cell_segments = explore_nearby(cell_lat, cell_lng, cell_size_km / 2)
        
        # Break if we got rate limited during explore_nearby
        if @rate_limited
          Rails.logger.warn "🛑 Stopping grid search due to rate limiting in explore_nearby. Processed #{processed_cells}/#{total_cells} cells."
          break
        end
        
        cell_segments.each do |seg|
          segments[seg.id] = seg
        end
        
        Rails.logger.info "Cell (#{lat_offset}, #{lng_offset}): found #{cell_segments.count} segments (#{processed_cells}/#{total_cells} cells processed)"
      end
      
      # Break out of outer loop too
      break if @rate_limited
    end
    
    # Log the keys of the segments hash
    Rails.logger.info "Segments hash keys: #{segments.keys.inspect}"
    
    segments.values
  end
  
  def explore_nearby(lat, lng, radius_km)
    offset = radius_km / 111.0
    lng_offset = radius_km / (111.0 * Math.cos(lat * Math::PI / 180))
    
    # Throttle requests to avoid rate limiting
    throttle_request
    
    retries = 0
    begin
      segments = @client.explore_segments(
        bounds: [lat - offset, lng - lng_offset, lat + offset, lng + lng_offset],
        activity_type: 'running'
      )
      
      # Log rate limit info after successful request
      log_rate_limit_info
      
      segments
    rescue Strava::Errors::Fault => e
      if e.http_status == 500 && retries < 3
        retries += 1
        sleep(2 ** retries)
        retry
      elsif e.http_status == 429
        @rate_limited = true
        Rails.logger.error "🛑 Rate limited in explore_segments! Daily or 15-minute limit exceeded"
        []
      else
        Rails.logger.error "Strava API error: #{e.message rescue e.inspect}"
        []
      end
    rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
      Rails.logger.error "🛑 Timeout in explore_segments - likely rate limiting. Stopping grid search: #{e.class.name}"
      @rate_limited = true
      []
    rescue => e
      # Check if it's a rate limit error
      if e.class.name.include?('RatelimitError') || e.message.include?('rate')
        @rate_limited = true
        Rails.logger.error "🛑 Rate limited in explore_segments! Daily or 15-minute limit exceeded"
        []
      else
        Rails.logger.error "Error exploring segments: #{e.message rescue e.inspect}"
        []
      end
    end
  end
  
  def parse_time_string(time_str)
    return nil unless time_str
    
    if time_str.is_a?(Integer) || time_str.is_a?(Float)
      return time_str.to_i
    elsif time_str.is_a?(String)
      if time_str.end_with?('s')
        return time_str[0..-2].to_i
      end
      
      if time_str =~ /^\d+$/
        return time_str.to_i
      end
      
      parts = time_str.split(':').map(&:to_i)
      
      case parts.length
      when 2
        parts[0] * 60 + parts[1]
      when 3
        parts[0] * 3600 + parts[1] * 60 + parts[2]
      else
        nil
      end
    else
      nil
    end
  end
  
  def fetch_kom_time_from_leaderboard(segment_id, segment_name)
    require 'net/http'
    require 'json'
    
    # Throttle requests to avoid rate limiting
    throttle_request
    
    begin
      uri = URI("https://www.strava.com/api/v3/segments/#{segment_id}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5   # Shorter timeout - if it's slow, it's likely rate limiting
      http.read_timeout = 10  # Shorter timeout
      
      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = "Bearer #{@access_token}"
      
      response = http.request(request)
      
      # Log rate limit info after each request
      log_rate_limit_info(response)
      
      if response.code == '200'
        data = JSON.parse(response.body)
        
        kom_time = nil
        
        if data['xoms'] && data['xoms']['kom']
          raw_kom = data['xoms']['kom']
          kom_time = parse_time_string(raw_kom)
        elsif data['xoms'] && data['xoms']['overall']  
          raw_kom = data['xoms']['overall']
          kom_time = parse_time_string(raw_kom)
        end
        
        if (!kom_time || kom_time == 0) && data['effort_count'] && data['effort_count'] > 0
          # LOG: We have to resort to fetch_kom_time
          Rails.logger.info "⚠️  Resorting to fetch_kom_time for segment #{segment_id} (#{segment_name}) - KOM not available in leaderboard"
          kom_time = fetch_kom_time(segment_id)
        end
        
        kom_time
        
      elsif response.code == '500'
        Rails.logger.warn "Strava 500 error for segment #{segment_id}, skipping"
        nil  # Just return nil instead of retrying
      elsif response.code == '429'
        Rails.logger.error "🛑 Rate limited! Setting rate_limited flag."
        @rate_limited = true
        # Increase delay for future requests
        @request_delay = [@request_delay * 2, 5.0].min
        Rails.logger.info "🐌 Increased request delay to #{@request_delay}s due to rate limiting"
        nil
      else
        Rails.logger.error "Failed to fetch segment #{segment_id}: #{response.code}"
        nil
      end
      
    rescue SocketError => e
      if e.message.include?("Hostname not known") || e.message.include?("nodename nor servname provided")
        Rails.logger.error "🛑 DNS resolution failed for segment #{segment_id} - likely soft rate limiting. Stopping processing: #{e.message}"
        @rate_limited = true
        nil
      else
        Rails.logger.error "🌐 Network error fetching segment #{segment_id}: #{e.message}"
        @rate_limited = true
        nil
      end
    rescue Timeout::Error, Net::OpenTimeout, Net::ReadTimeout => e
      Rails.logger.error "🛑 Timeout for segment #{segment_id} - likely soft rate limiting. Stopping processing: #{e.class.name}"
      @rate_limited = true
      # Increase delay for future requests
      @request_delay = [@request_delay * 2, 5.0].min
      Rails.logger.info "🐌 Increased request delay to #{@request_delay}s due to timeout"
      nil
    rescue => e
      Rails.logger.error "❌ Error fetching segment #{segment_id}: #{e.class.name} - #{e.message}"
      nil
    end
  end
  
  def fetch_kom_time(segment_id)
    require 'net/http'
    require 'json'
    
    # Throttle requests to avoid rate limiting
    throttle_request
    
    begin
      uri = URI("https://www.strava.com/api/v3/segment_efforts?segment_id=#{segment_id}&per_page=200")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5   # Shorter timeout
      http.read_timeout = 10  # Shorter timeout
      
      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = "Bearer #{@access_token}"
      
      response = http.request(request)
      
      # Log rate limit info after each request
      log_rate_limit_info(response)
      
      if response.code == '200'
        data = JSON.parse(response.body)
        if data.any?
          fastest = data.min_by { |effort| effort['elapsed_time'].to_i }
          time = fastest['elapsed_time'].to_i if fastest
          Rails.logger.info "✅ Successfully fetched KOM time via segment_efforts for segment #{segment_id}: #{time}s"
          time
        else
          nil
        end
      elsif response.code == '429'
        Rails.logger.error "🛑 Rate limited in fetch_kom_time! Setting rate_limited flag."
        @rate_limited = true
        # Increase delay for future requests
        @request_delay = [@request_delay * 2, 5.0].min
        Rails.logger.info "🐌 Increased request delay to #{@request_delay}s due to rate limiting"
        nil
      else
        Rails.logger.warn "Failed to fetch efforts for segment #{segment_id}: #{response.code}"
        nil
      end
      
    rescue SocketError => e
      if e.message.include?("Hostname not known") || e.message.include?("nodename nor servname provided")
        Rails.logger.error "🛑 DNS resolution failed for segment efforts #{segment_id} - likely soft rate limiting. Stopping processing: #{e.message}"
        @rate_limited = true
        nil
      else
        Rails.logger.error "🌐 Network error fetching efforts for segment #{segment_id}: #{e.message}"
        @rate_limited = true
        nil
      end
    rescue Timeout::Error, Net::OpenTimeout, Net::ReadTimeout => e
      Rails.logger.error "🛑 Timeout for segment efforts #{segment_id} - likely soft rate limiting. Stopping processing: #{e.class.name}"
      @rate_limited = true
      # Increase delay for future requests
      @request_delay = [@request_delay * 2, 5.0].min
      Rails.logger.info "🐌 Increased request delay to #{@request_delay}s due to timeout"
      nil
    rescue => e
      Rails.logger.error "❌ Error fetching efforts for segment #{segment_id}: #{e.class.name} - #{e.message}"
      nil
    end
  end
  
  # Helper method to throttle API requests
  def throttle_request
    time_since_last = Time.current - @last_request_time
    if time_since_last < @request_delay
      sleep_time = @request_delay - time_since_last
      Rails.logger.debug "🐌 Throttling request - sleeping for #{sleep_time.round(2)}s"
      sleep(sleep_time)
    end
    @last_request_time = Time.current
  end
  
  # Helper method to log rate limit information
  def log_rate_limit_info(response = nil)
    if response
      # Extract rate limit headers from Strava API response
      daily_limit = response['X-RateLimit-Limit']
      daily_usage = response['X-RateLimit-Usage'] 
      short_limit = response['X-RateLimit-Short-Limit']
      short_usage = response['X-RateLimit-Short-Usage']
      
      if daily_limit && daily_usage
        daily_remaining = daily_limit.to_i - daily_usage.to_i
        daily_percent = (daily_usage.to_f / daily_limit.to_f * 100).round(1)
        Rails.logger.info "🔄 Rate limit - Daily: #{daily_usage}/#{daily_limit} (#{daily_percent}%, #{daily_remaining} remaining)"
        
        # Adjust throttling based on usage
        if daily_percent > 80
          @request_delay = [@request_delay * 1.5, 3.0].min
          Rails.logger.info "🐌 Increased delay to #{@request_delay}s - high daily usage (#{daily_percent}%)"
        end
      end
      
      if short_limit && short_usage
        short_remaining = short_limit.to_i - short_usage.to_i  
        short_percent = (short_usage.to_f / short_limit.to_f * 100).round(1)
        Rails.logger.info "🔄 Rate limit - 15min: #{short_usage}/#{short_limit} (#{short_percent}%, #{short_remaining} remaining)"
        
        # Adjust throttling based on 15-minute usage
        if short_percent > 70
          @request_delay = [@request_delay * 2, 5.0].min
          Rails.logger.info "🐌 Increased delay to #{@request_delay}s - high 15min usage (#{short_percent}%)"
        elsif short_percent < 30 && @request_delay > 0.5
          @request_delay = [@request_delay * 0.8, 0.5].max
          Rails.logger.info "🏃 Decreased delay to #{@request_delay}s - low 15min usage (#{short_percent}%)"
        end
      end
    else
      # For non-HTTP requests (like the Strava gem), we can't get headers but can still log that we made a request
      Rails.logger.info "🔄 API request made (rate limit info not available for this request type)"
    end
  end
end