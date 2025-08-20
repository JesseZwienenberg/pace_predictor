# app/services/easy_segment_finder.rb
class EasySegmentFinder
  def initialize(access_token)
    @client = Strava::Api::Client.new(access_token: access_token)
    @access_token = access_token
  end
  
  def find(lat, lng, max_radius_km, max_segment_distance_m = 5000, max_pace_min_km = nil)
    # Get segments from multiple overlapping areas to find more
    all_segments = fetch_segments_in_grid(lat, lng, max_radius_km)
    
    Rails.logger.info "Found #{all_segments.count} total segments to check"
    
    results = all_segments.map do |seg|
      next if seg.distance > max_segment_distance_m
      
      # Get the actual KOM from leaderboard
      kom_time = fetch_kom_time_from_leaderboard(seg.id, seg.name)
      
      if !kom_time || kom_time == 0
        Rails.logger.info "No valid KOM found for #{seg.name}"
        next
      end
      
      kom_pace = (kom_time / 60.0) / (seg.distance / 1000.0)
      
      # Sanity check - no human can run faster than 1:00 min/km
      if kom_pace < 1.0
        Rails.logger.warn "Invalid KOM pace #{kom_pace.round(2)} for #{seg.name}, skipping"
        next
      end
      
      if max_pace_min_km && max_pace_min_km > 0 && kom_pace < max_pace_min_km
        Rails.logger.info "Skipping #{seg.name}: KOM pace #{kom_pace.round(2)} < max pace #{max_pace_min_km}"
        next
      end
      
      ratio = ::SegmentAnalyzer.difficulty_ratio(seg.distance, kom_time)
      
      if !ratio
        Rails.logger.info "No matching effort for #{seg.name} at #{seg.distance}m"
        next
      end
      
      Rails.logger.info "Including #{seg.name}: KOM #{kom_time}s (#{kom_pace.round(2)} min/km), ratio #{ratio.round(2)}"
      
      {
        id: seg.id,
        name: seg.name,
        distance: seg.distance,
        kom_time: kom_time,
        kom_pace: kom_pace,
        difficulty_ratio: ratio,
        my_predicted_pace: AllTimeBestEffort.find_by(
          distance_meters: (seg.distance / 10.0).round * 10
        )&.pace_min_per_km
      }
    end.compact
    
    Rails.logger.info "Returning #{results.count} segments after filtering"
    results.sort_by { |s| -s[:difficulty_ratio] }
  end
  
  private
  
  def fetch_segments_in_grid(center_lat, center_lng, radius_km)
    segments = {}
    
    # Create a grid of smaller search areas
    # Each cell is about 2km wide to ensure good coverage
    cell_size_km = 2.0
    num_cells = (radius_km / cell_size_km).ceil
    
    (-num_cells..num_cells).each do |lat_offset|
      (-num_cells..num_cells).each do |lng_offset|
        # Calculate center of this grid cell
        lat_shift = lat_offset * cell_size_km / 111.0
        lng_shift = lng_offset * cell_size_km / (111.0 * Math.cos(center_lat * Math::PI / 180))
        
        cell_lat = center_lat + lat_shift
        cell_lng = center_lng + lng_shift
        
        # Skip if this cell is outside our radius
        distance_from_center = Math.sqrt((lat_shift * 111)**2 + (lng_shift * 111 * Math.cos(center_lat * Math::PI / 180))**2)
        next if distance_from_center > radius_km
        
        # Fetch segments for this cell
        cell_segments = explore_nearby(cell_lat, cell_lng, cell_size_km / 2)
        
        # Add to hash using segment ID as key to avoid duplicates
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
    
    begin
      @client.explore_segments(
        bounds: [lat - offset, lng - lng_offset, lat + offset, lng + lng_offset],
        activity_type: 'running'
      )
    rescue => e
      Rails.logger.error "Error exploring segments: #{e.message}"
      []
    end
  end
  
  def parse_time_string(time_str)
    return nil unless time_str
    
    # Handle different time formats
    if time_str.is_a?(Integer) || time_str.is_a?(Float)
      # Already in seconds, return as-is
      return time_str.to_i
    elsif time_str.is_a?(String)
      # Handle "54s" format (remove the 's' and parse as integer)
      if time_str.end_with?('s')
        return time_str[0..-2].to_i
      end
      
      # Check if it's already a number as string
      if time_str =~ /^\d+$/
        return time_str.to_i
      end
      
      # Parse "3:25" or "1:03:25" format
      parts = time_str.split(':').map(&:to_i)
      
      case parts.length
      when 2  # "3:25" = 3 minutes, 25 seconds
        parts[0] * 60 + parts[1]
      when 3  # "1:03:25" = 1 hour, 3 minutes, 25 seconds
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
    
    # Use the segments/:id endpoint which includes leaderboard data
    uri = URI("https://www.strava.com/api/v3/segments/#{segment_id}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{@access_token}"
    
    response = http.request(request)
    
    if response.code == '200'
      data = JSON.parse(response.body)
      
      # Check different possible locations for KOM time
      kom_time = nil
      
      if data['xoms'] && data['xoms']['kom']
        raw_kom = data['xoms']['kom']
        kom_time = parse_time_string(raw_kom)
      elsif data['xoms'] && data['xoms']['overall']  
        raw_kom = data['xoms']['overall']
        kom_time = parse_time_string(raw_kom)
      end
      
      if (!kom_time || kom_time == 0) && data['effort_count'] && data['effort_count'] > 0
        Rails.logger.info "No KOM in segment data, fetching efforts for #{segment_name}"
        # If no KOM in main data, try fetching efforts separately
        kom_time = fetch_kom_time(segment_id)
      end
      
      kom_time
    else
      Rails.logger.error "Failed to fetch segment #{segment_id}: #{response.code}"
      nil
    end
  rescue => e
    Rails.logger.error "Error fetching segment: #{e.message}"
    nil
  end
  
  def fetch_kom_time(segment_id)
    require 'net/http'
    require 'json'
    
    uri = URI("https://www.strava.com/api/v3/segment_efforts?segment_id=#{segment_id}&per_page=200")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{@access_token}"
    
    response = http.request(request)
    
    if response.code == '200'
      data = JSON.parse(response.body)
      if data.any?
        # Get the fastest time from all efforts
        fastest = data.min_by { |effort| effort['elapsed_time'].to_i }
        time = fastest['elapsed_time'].to_i if fastest
        Rails.logger.info "Fastest effort time: #{time}s from #{data.length} efforts"
        time
      end
    else
      Rails.logger.warn "Failed to fetch efforts: #{response.code}"
      nil
    end
  rescue => e
    Rails.logger.error "Error fetching efforts: #{e.message}"
    nil
  end
end