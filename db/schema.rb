# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_08_13_130415) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "activities", force: :cascade do |t|
    t.bigint "strava_id"
    t.string "name"
    t.float "distance"
    t.integer "duration"
    t.float "pace"
    t.datetime "start_date"
    t.integer "average_heartrate"
    t.float "elevation_gain"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.float "average_speed"
    t.float "max_speed"
    t.integer "elapsed_time"
    t.string "activity_type"
  end

  create_table "best_efforts", force: :cascade do |t|
    t.bigint "activity_id", null: false
    t.string "name"
    t.integer "elapsed_time"
    t.integer "moving_time"
    t.float "distance"
    t.integer "start_index"
    t.integer "end_index"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["activity_id"], name: "index_best_efforts_on_activity_id"
  end

  create_table "splits", force: :cascade do |t|
    t.bigint "activity_id", null: false
    t.float "distance"
    t.integer "elapsed_time"
    t.float "elevation_difference"
    t.integer "moving_time"
    t.integer "split"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["activity_id"], name: "index_splits_on_activity_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email"
    t.string "strava_uid"
    t.string "access_token"
    t.string "refresh_token"
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "best_efforts", "activities"
  add_foreign_key "splits", "activities"
end
