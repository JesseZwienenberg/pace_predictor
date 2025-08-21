# db/migrate/xxx_create_cached_segments.rb
class CreateCachedSegments < ActiveRecord::Migration[7.0]
  def change
    create_table :cached_segments do |t|
      t.bigint :strava_id, null: false, index: { unique: true }
      t.string :name
      t.float :distance
      t.integer :kom_time
      t.timestamps
    end
  end
end