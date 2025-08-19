class CreateAllTimeBestEfforts < ActiveRecord::Migration[8.0]
  def change
    create_table :all_time_best_efforts do |t|
      t.integer :distance_meters, null: false
      t.float :pace_min_per_km, null: false
      t.bigint :activity_id
      t.datetime :achieved_at
      t.timestamps
    end

    add_index :all_time_best_efforts, :distance_meters, unique: true
    add_index :all_time_best_efforts, :pace_min_per_km
    add_foreign_key :all_time_best_efforts, :activities
  end
end