class AddMarkingFieldsToCachedSegments < ActiveRecord::Migration[8.0]
  def change
    add_column :cached_segments, :is_done, :boolean, default: false
    add_column :cached_segments, :is_favorited, :boolean, default: false
    add_column :cached_segments, :is_unavailable, :boolean, default: false
  end
end
