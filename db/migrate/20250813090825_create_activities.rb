class CreateActivities < ActiveRecord::Migration[8.0]
  def change
    create_table :activities do |t|
      t.integer :strava_id
      t.string :name
      t.float :distance
      t.integer :duration
      t.float :pace
      t.datetime :start_date
      t.integer :average_heartrate
      t.float :elevation_gain

      t.timestamps
    end
  end
end
