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

ActiveRecord::Schema[8.1].define(version: 2026_09_02_153535) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "postgis"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "journeys", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.decimal "distance_meters"
    t.text "encoded_polyline", null: false
    t.integer "estimated_duration_seconds"
    t.integer "estimated_steps"
    t.string "location_name"
    t.string "name"
    t.boolean "recommendable", default: false, null: false
    t.geography "start_point", limit: {:srid=>4326, :type=>"st_point", :geographic=>true}, null: false
    t.string "theme_key"
    t.datetime "updated_at", null: false
    t.index ["start_point"], name: "index_journeys_on_start_point", using: :gist
    t.index ["theme_key"], name: "index_journeys_on_theme_key"
  end

  create_table "saved_journeys", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "journey_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["journey_id"], name: "index_saved_journeys_on_journey_id"
    t.index ["user_id", "journey_id"], name: "index_saved_journeys_on_user_id_and_journey_id", unique: true
    t.index ["user_id"], name: "index_saved_journeys_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.float "current_latitude"
    t.string "current_location_name"
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
    t.string "mood_before"
    t.float "photo_latitude"
    t.float "photo_longitude"
    t.integer "rating"
    t.text "reflection"
    t.text "review"
    t.text "share_quote"
    t.datetime "shared_at"
    t.datetime "started_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["journey_id"], name: "index_walks_on_journey_id"
    t.index ["shared_at"], name: "index_walks_on_shared_at"
    t.index ["user_id"], name: "index_walks_on_user_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "saved_journeys", "journeys"
  add_foreign_key "saved_journeys", "users"
  add_foreign_key "walks", "journeys"
  add_foreign_key "walks", "users"
end
