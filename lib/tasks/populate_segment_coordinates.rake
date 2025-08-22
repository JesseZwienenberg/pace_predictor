namespace :segments do
  desc "Populate coordinates for cached segments that are missing them"
  task populate_coordinates: :environment do
    require 'net/http'
    require 'json'
    
    segments_without_coords = CachedSegment.where(start_latitude: nil).limit(100)
    
    if segments_without_coords.empty?
      puts "✅ All cached segments already have coordinates!"
      exit
    end
    
    puts "📍 Found #{segments_without_coords.count} segments without coordinates"
    puts "⚠️  This will use #{segments_without_coords.count} API calls"
    print "Continue? (y/N): "
    
    response = STDIN.gets.chomp.downcase
    unless response == 'y' || response == 'yes'
      puts "❌ Cancelled"
      exit
    end
    
    # Get access token from user (you'll need to provide this)
    print "Enter your Strava access token: "
    access_token = STDIN.gets.chomp
    
    if access_token.empty?
      puts "❌ Access token required"
      exit
    end
    
    updated_count = 0
    failed_count = 0
    
    segments_without_coords.each_with_index do |segment, index|
      puts "📍 (#{index + 1}/#{segments_without_coords.count}) Fetching coordinates for #{segment.name}..."
      
      begin
        uri = URI("https://www.strava.com/api/v3/segments/#{segment.strava_id}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 10
        
        request = Net::HTTP::Get.new(uri)
        request['Authorization'] = "Bearer #{access_token}"
        
        response = http.request(request)
        
        if response.code == '200'
          data = JSON.parse(response.body)
          
          if data['start_latlng'] && data['start_latlng'].length == 2
            segment.update!(
              start_latitude: data['start_latlng'][0],
              start_longitude: data['start_latlng'][1]
            )
            updated_count += 1
            puts "  ✅ Updated: #{data['start_latlng']}"
          else
            puts "  ⚠️  No coordinates available"
            failed_count += 1
          end
        elsif response.code == '429'
          puts "  🛑 Rate limited! Stopping..."
          break
        else
          puts "  ❌ Failed: #{response.code}"
          failed_count += 1
        end
        
        # Throttle requests
        sleep(0.5)
        
      rescue => e
        puts "  ❌ Error: #{e.message}"
        failed_count += 1
      end
    end
    
    puts "\\n📊 Results:"
    puts "  ✅ Updated: #{updated_count}"
    puts "  ❌ Failed: #{failed_count}"
    puts "  🔄 Remaining: #{CachedSegment.where(start_latitude: nil).count}"
  end
end