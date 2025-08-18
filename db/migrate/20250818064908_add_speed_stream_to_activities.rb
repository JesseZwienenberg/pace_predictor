class AddSpeedStreamToActivities < ActiveRecord::Migration[8.0]
  def change
    add_column :activities, :speed_stream, :json
  end
end
