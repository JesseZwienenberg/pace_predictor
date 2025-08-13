class CreateBestEfforts < ActiveRecord::Migration[8.0]
  def change
    create_table :best_efforts do |t|
      t.references :activity, null: false, foreign_key: true
      t.string :name
      t.integer :elapsed_time
      t.integer :moving_time
      t.float :distance
      t.integer :start_index
      t.integer :end_index

      t.timestamps
    end
  end
end
