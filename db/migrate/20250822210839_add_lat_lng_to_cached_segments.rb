class AddLatLngToCachedSegments < ActiveRecord::Migration[8.0]
  def change
    add_column :cached_segments, :start_latitude, :decimal, precision: 10, scale: 6
    add_column :cached_segments, :start_longitude, :decimal, precision: 10, scale: 6
  end
end
