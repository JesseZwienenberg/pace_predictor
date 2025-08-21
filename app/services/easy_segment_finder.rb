# app/services/easy_segment_finder.rb
class EasySegmentFinder
  def initialize(access_token)
    @client = Strava::Api::Client.new(access_token: access_token)
    @access_token = access_token
    @rate_limited = false
  end
  
  def find(lat, lng, max_radius_km, max_segment_distance_m = 5000, max_pace_min_km = nil)
    all_segments = fetch_segments_in_grid(lat, lng, max_radius_km)
    
    # Check if we got rate limited during segment fetching
    if @rate_limited
      raise "Rate limited! Daily limit exceeded. Please wait until tomorrow to search again."
    end
    
    Rails.logger.info "Found #{all_segments.count} total segments to check"
    
    results = all_segments.map do |seg|
      next if seg.distance > max_segment_distance_m
      
      # Check cache first
      cached = CachedSegment.find_by(strava_id: seg.id)
      
      if cached
        kom_time = cached.kom_time
        Rails.logger.info "Using cached KOM for #{seg.name}: #{kom_time}s"
      else
        # Fetch from API and cache it
        kom_time = fetch_kom_time_from_leaderboard(seg.id, seg.name)
        
        if kom_time && kom_time > 0
          CachedSegment.create!(
            strava_id: seg.id,
            name: seg.name,
            distance: seg.distance,
            kom_time: kom_time
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
      
      {
        id: seg.id,
        name: seg.name,
        distance: seg.distance,
        kom_time: kom_time,
        kom_pace: kom_pace,
        difficulty_ratio: ratio
      }
    end.compact
    
    Rails.logger.info "Returning #{results.count} segments after filtering"
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
          kom_time: kom_time
        )
      end
    end
    
    kom_time
  end
  
  private
  
  # Keep all your existing private methods exactly as they are
  # fetch_segments_in_grid, explore_nearby, parse_time_string, fetch_kom_time_from_leaderboard, fetch_kom_time
  # ... (no changes needed to these methods)
  
  def fetch_segments_in_grid(center_lat, center_lng, radius_km)
    segments = {}
    cell_size_km = 2.0
    num_cells = (radius_km / cell_size_km).ceil
    
    (-num_cells..num_cells).each do |lat_offset|
      (-num_cells..num_cells).each do |lng_offset|
        lat_shift = lat_offset * cell_size_km / 111.0
        lng_shift = lng_offset * cell_size_km / (111.0 * Math.cos(center_lat * Math::PI / 180))
        
        cell_lat = center_lat + lat_shift
        cell_lng = center_lng + lng_shift
        
        distance_from_center = Math.sqrt((lat_shift * 111)**2 + (lng_shift * 111 * Math.cos(center_lat * Math::PI / 180))**2)
        next if distance_from_center > radius_km
        
        cell_segments = explore_nearby(cell_lat, cell_lng, cell_size_km / 2)
        
        cell_segments.each do |seg|
          segments[seg.id] = seg
        end
        
        Rails.logger.info "Cell (#{lat_offset}, #{lng_offset}): found #{cell_segments.count} segments"
      end
    end
    
    segments.values
  end
  
  def explore_nearby(lat, lng, radius_km)
    offset = radius_km / 111.0
    lng_offset = radius_km / (111.0 * Math.cos(lat * Math::PI / 180))
    
    retries = 0
    begin
      segments = @client.explore_segments(
        bounds: [lat - offset, lng - lng_offset, lat + offset, lng + lng_offset],
        activity_type: 'running'
      )
      segments
    rescue Strava::Errors::Fault => e
      if e.http_status == 500 && retries < 3
        retries += 1
        sleep(2 ** retries)
        retry
      elsif e.http_status == 429
        @rate_limited = true
        Rails.logger.error "Rate limited! Daily or 15-minute limit exceeded"
        []
      else
        Rails.logger.error "Strava API error: #{e.message rescue e.inspect}"
        []
      end
    rescue => e
      # Check if it's a rate limit error
      if e.class.name.include?('RatelimitError')
        @rate_limited = true
        Rails.logger.error "Rate limited! Daily or 15-minute limit exceeded"
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
    
    retries = 0
    begin
      uri = URI("https://www.strava.com/api/v3/segments/#{segment_id}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      
      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = "Bearer #{@access_token}"
      
      response = http.request(request)
      
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
          kom_time = fetch_kom_time(segment_id)
        end
        
        kom_time
        
      elsif response.code == '500'
        Rails.logger.warn "Strava 500 error for segment #{segment_id}, skipping"
        nil  # Just return nil instead of retrying
      elsif response.code == '429'
        Rails.logger.error "Rate limited!"
        nil
      else
        Rails.logger.error "Failed to fetch segment #{segment_id}: #{response.code}"
        nil
      end
      
    rescue => e
      Rails.logger.error "Error fetching segment #{segment_id}: #{e.message}"
      nil
    end
  end
  
  def fetch_kom_time(segment_id)
    require 'net/http'
    require 'json'
    
    begin
      uri = URI("https://www.strava.com/api/v3/segment_efforts?segment_id=#{segment_id}&per_page=200")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      
      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = "Bearer #{@access_token}"
      
      response = http.request(request)
      
      if response.code == '200'
        data = JSON.parse(response.body)
        if data.any?
          fastest = data.min_by { |effort| effort['elapsed_time'].to_i }
          time = fastest['elapsed_time'].to_i if fastest
          time
        else
          nil
        end
      else
        Rails.logger.warn "Failed to fetch efforts for segment #{segment_id}: #{response.code}"
        nil
      end
    rescue => e
      Rails.logger.error "Error fetching efforts: #{e.message}"
      nil
    end
  end
end