class CreateSplits < ActiveRecord::Migration[8.0]
  def change
    create_table :splits do |t|
      t.references :activity, null: false, foreign_key: true
      t.float :distance
      t.integer :elapsed_time
      t.float :elevation_difference
      t.integer :moving_time
      t.integer :split

      t.timestamps
    end
  end
end
