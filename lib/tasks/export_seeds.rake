namespace :db do
  desc "Export current database to demo_seeds.rb file"
  task export_demo_seeds: :environment do
    File.open("#{Rails.root}/db/demo_seeds.rb", "w") do |file|
      file.puts "# Demo seed data generated on #{Date.current}"
      file.puts "puts 'Loading demo data...'"
      file.puts ""
      
      # Activity records
      if Activity.count > 0
        file.puts "# Activities (#{Activity.count} records)"
        Activity.all.each do |activity|
          attrs = activity.attributes.except('id', 'created_at', 'updated_at')
          # Convert datetime fields to Time.parse calls
          attrs.each do |key, value|
            if value.is_a?(ActiveSupport::TimeWithZone) || value.is_a?(Time)
              attrs[key] = "Time.parse('#{value.strftime('%Y-%m-%d %H:%M:%S %z')}')"
            end
          end
          
          # Build the create statement manually to handle Time.parse
          attr_string = attrs.map do |key, value|
            if value.is_a?(String) && value.start_with?('Time.parse')
              "#{key.inspect} => #{value}"
            else
              "#{key.inspect} => #{value.inspect}"
            end
          end.join(", ")
          
          file.puts "Activity.create!(#{attr_string})"
        end
        file.puts ""
      end
      
      # BestEffort records
      if BestEffort.count > 0
        file.puts "# Best Efforts (#{BestEffort.count} records)"
        BestEffort.all.each do |best_effort|
          attrs = best_effort.attributes.except('id', 'created_at', 'updated_at')
          attrs.each do |key, value|
            if value.is_a?(ActiveSupport::TimeWithZone) || value.is_a?(Time)
              attrs[key] = "Time.parse('#{value.strftime('%Y-%m-%d %H:%M:%S %z')}')"
            end
          end
          
          attr_string = attrs.map do |key, value|
            if value.is_a?(String) && value.start_with?('Time.parse')
              "#{key.inspect} => #{value}"
            else
              "#{key.inspect} => #{value.inspect}"
            end
          end.join(", ")
          
          file.puts "BestEffort.create!(#{attr_string})"
        end
        file.puts ""
      end
      
      # Split records
      if Split.count > 0
        file.puts "# Splits (#{Split.count} records)"
        Split.all.each do |split|
          attrs = split.attributes.except('id', 'created_at', 'updated_at')
          attrs.each do |key, value|
            if value.is_a?(ActiveSupport::TimeWithZone) || value.is_a?(Time)
              attrs[key] = "Time.parse('#{value.strftime('%Y-%m-%d %H:%M:%S %z')}')"
            end
          end
          
          attr_string = attrs.map do |key, value|
            if value.is_a?(String) && value.start_with?('Time.parse')
              "#{key.inspect} => #{value}"
            else
              "#{key.inspect} => #{value.inspect}"
            end
          end.join(", ")
          
          file.puts "Split.create!(#{attr_string})"
        end
        file.puts ""
      end
      
      file.puts "puts 'Demo data loaded successfully!'"
    end
    
    puts "Demo seeds exported to db/demo_seeds.rb"
    puts "Records exported:"
    puts "- Activities: #{Activity.count}"
    puts "- BestEfforts: #{BestEffort.count}" 
    puts "- Splits: #{Split.count}"
  end

  desc "Load demo seeds from demo_seeds.rb"
  task load_demo_seeds: :environment do
    demo_seeds_file = "#{Rails.root}/db/demo_seeds.rb"
    
    if File.exist?(demo_seeds_file)
      load demo_seeds_file
      puts "Demo seeds loaded successfully!"
    else
      puts "Demo seeds file not found at db/demo_seeds.rb"
      puts "Run 'rails db:export_demo_seeds' first to create it."
    end
  end

  desc "Reset database and load demo data"
  task reset_with_demo: :environment do
    Rake::Task['db:reset'].invoke
    Rake::Task['db:load_demo_seeds'].invoke
  end

  desc "Clear all data but keep schema"
  task clear_data: :environment do
    # Disable foreign key checks
    ActiveRecord::Base.connection.execute("SET FOREIGN_KEY_CHECKS = 0") if ActiveRecord::Base.connection.adapter_name.downcase.include?('mysql')
    
    # Clear data in reverse dependency order
    Split.delete_all
    BestEffort.delete_all  
    Activity.delete_all
    
    # Re-enable foreign key checks
    ActiveRecord::Base.connection.execute("SET FOREIGN_KEY_CHECKS = 1") if ActiveRecord::Base.connection.adapter_name.downcase.include?('mysql')
    
    puts "All data cleared, schema intact"
  end
end