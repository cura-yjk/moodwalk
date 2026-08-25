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

ActiveRecord::Schema[8.1].define(version: 2026_08_25_012336) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "postgis"

  create_table "journeys", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.decimal "distance_meters"
    t.text "encoded_polyline", null: false
    t.integer "estimated_duration_seconds"
    t.integer "estimated_steps"
    t.string "name"
    t.geography "start_point", limit: {:srid=>4326, :type=>"st_point", :geographic=>true}, null: false
    t.datetime "updated_at", null: false
    t.index ["start_point"], name: "index_journeys_on_start_point", using: :gist
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.float "current_latitude"
    t.float "current_longitude"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "name"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "walks", force: :cascade do |t|
    t.decimal "actual_distance"
    t.integer "actual_steps"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.bigint "journey_id", null: false
    t.string "mood_after"
    t.text "reflection"
    t.datetime "started_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["journey_id"], name: "index_walks_on_journey_id"
    t.index ["user_id"], name: "index_walks_on_user_id"
  end

  add_foreign_key "walks", "journeys"
  add_foreign_key "walks", "users"
end
