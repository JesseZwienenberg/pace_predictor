# lib/tasks/recompute_best_efforts.rake
namespace :best_efforts do
  desc "Recompute all_best_efforts from existing speed_stream data"
  task :recompute_from_speed_streams, [:force] => :environment do |_, args|
    # Check if force flag is set (to overwrite existing all_best_efforts)
    force_recompute = args[:force] == 'true'
    
    puts "=" * 60
    puts "Starting recomputation of best efforts from speed streams"
    puts "Force mode: #{force_recompute ? 'ON (will overwrite existing)' : 'OFF (only empty ones)'}"
    puts "=" * 60
    
    # Find activities to process
    activities = if force_recompute
      Activity.where.not(speed_stream: nil)
    else
      Activity.where.not(speed_stream: nil).where(all_best_efforts: nil)
    end
    
    total_count = activities.count
    processed_count = 0
    error_count = 0
    
    puts "Found #{total_count} activities to process\n\n"
    
    activities.find_each.with_index do |activity, index|
      begin
        print "[#{index + 1}/#{total_count}] Processing activity ##{activity.id} - #{activity.name}... "
        
        # Extract speeds_mps from speed_stream
        speed_stream = activity.speed_stream
        
        # Handle both symbol and string keys since JSON might store as strings
        speeds_mps = speed_stream['speeds_mps'] || speed_stream[:speeds_mps]
        
        if speeds_mps.nil? || speeds_mps.empty?
          puts "SKIPPED (no speed data)"
          next
        end
        
        # Recompute best efforts using the same method as in the controller
        best_efforts = find_min_consecutive_for_multiples_of_10(speeds_mps)
        
        if best_efforts.nil? || best_efforts.empty?
          puts "SKIPPED (could not compute best efforts)"
          next
        end
        
        # Update the activity with new best efforts
        activity.update!(all_best_efforts: best_efforts)
        
        processed_count += 1
        puts "SUCCESS (#{best_efforts.length} distances computed)"
        
      rescue => e
        error_count += 1
        puts "ERROR: #{e.message}"
        puts "  Backtrace: #{e.backtrace.first(3).join("\n  ")}" if Rails.env.development?
      end
    end
    
    puts "\n" + "=" * 60
    puts "Recomputation complete!"
    puts "Processed: #{processed_count}/#{total_count} activities"
    puts "Errors: #{error_count}" if error_count > 0
    puts "=" * 60
    
    # Now update the all-time best efforts
    puts "\nUpdating all-time best efforts..."
    update_all_time_best_efforts
    
    puts "\nDone!"
  end
  
  desc "Recompute and force overwrite all best efforts (even non-empty ones)"
  task recompute_all: :environment do
    Rake::Task['best_efforts:recompute_from_speed_streams'].invoke('true')
  end
  
  private
  
  # Your actual implementation from the controller
  def find_min_consecutive_for_multiples_of_10(speeds)
    total_sum = speeds.sum
    max_target = (total_sum / 10).floor * 10

    return [] if max_target == 0
    
    results = []

    index = 0
    
    (10..max_target).step(10) do |target|
      index += 1
      min_length = Float::INFINITY
      current_sum = 0
      left = 0
      
      speeds.each_with_index do |speed, right|
        current_sum += speed
        
        while current_sum >= target
          min_length = [min_length, right - left + 1].min
          current_sum -= speeds[left]
          left += 1
        end
      end
      
      results << min_length * 100.0 / index / 60
    end

    results
  end
  
  def update_all_time_best_efforts
    # Clear and recalculate all-time best efforts
    AllTimeBestEffort.destroy_all
    
    Activity.where.not(all_best_efforts: nil).find_each do |activity|
      activity.send(:update_all_time_best_efforts) if activity.all_best_efforts.present?
    end
    
    puts "All-time best efforts updated! Total records: #{AllTimeBestEffort.count}"
  end
end