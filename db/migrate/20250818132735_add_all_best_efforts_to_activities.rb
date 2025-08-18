class AddAllBestEffortsToActivities < ActiveRecord::Migration[8.0]
  def change
    add_column :activities, :all_best_efforts, :json
  end
end
