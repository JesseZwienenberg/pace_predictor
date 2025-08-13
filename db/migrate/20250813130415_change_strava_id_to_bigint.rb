class ChangeStravaIdToBigint < ActiveRecord::Migration[8.0]
  def change
    change_column :activities, :strava_id, :bigint
  end
end
