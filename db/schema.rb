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

ActiveRecord::Schema[8.0].define(version: 2025_08_24_103442) do
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
    t.json "speed_stream"
    t.json "all_best_efforts"
  end

  create_table "all_time_best_efforts", force: :cascade do |t|
    t.integer "distance_meters", null: false
    t.float "pace_min_per_km", null: false
    t.bigint "activity_id"
    t.datetime "achieved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["distance_meters"], name: "index_all_time_best_efforts_on_distance_meters", unique: true
    t.index ["pace_min_per_km"], name: "index_all_time_best_efforts_on_pace_min_per_km"
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

  create_table "cached_segments", force: :cascade do |t|
    t.bigint "strava_id", null: false
    t.string "name"
    t.float "distance"
    t.integer "kom_time"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "start_latitude", precision: 10, scale: 6
    t.decimal "start_longitude", precision: 10, scale: 6
    t.boolean "is_done", default: false
    t.boolean "is_favorited", default: false
    t.boolean "is_unavailable", default: false
    t.index ["strava_id"], name: "index_cached_segments_on_strava_id", unique: true
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

  add_foreign_key "all_time_best_efforts", "activities"
  add_foreign_key "best_efforts", "activities"
  add_foreign_key "splits", "activities"
end
