class AddFieldsToActivities < ActiveRecord::Migration[8.0]
  def change
    add_column :activities, :average_speed, :float
    add_column :activities, :max_speed, :float
    add_column :activities, :elapsed_time, :integer
    add_column :activities, :activity_type, :string
  end
end
