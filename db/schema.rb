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

ActiveRecord::Schema[8.1].define(version: 2026_10_09_165143) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "btree_gist"
  enable_extension "pg_catalog.plpgsql"

  create_table "leave_request_events", force: :cascade do |t|
    t.bigint "leave_request_id", null: false
    t.bigint "actor_id", null: false
    t.integer "event_type", null: false
    t.integer "from_status"
    t.integer "to_status", null: false
    t.text "comment"
    t.datetime "occurred_at", null: false
    t.index ["actor_id"], name: "index_leave_request_events_on_actor_id"
    t.index ["leave_request_id"], name: "index_leave_request_events_on_leave_request_id"
    t.check_constraint "event_type = ANY (ARRAY[0, 1, 2, 3])", name: "leave_request_events_valid_type"
    t.check_constraint "to_status = ANY (ARRAY[0, 1, 2, 3])", name: "leave_request_events_valid_to_status"
  end

  create_table "leave_requests", force: :cascade do |t|
    t.bigint "employee_id", null: false
    t.bigint "leave_type_id", null: false
    t.date "starts_on", null: false
    t.date "ends_on", null: false
    t.integer "status", default: 0, null: false
    t.text "employee_comment"
    t.text "review_comment"
    t.bigint "reviewer_id"
    t.datetime "reviewed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "start_part", default: 0, null: false
    t.integer "end_part", default: 1, null: false
    t.index ["employee_id"], name: "index_leave_requests_on_employee_id"
    t.index ["leave_type_id"], name: "index_leave_requests_on_leave_type_id"
    t.index ["reviewer_id"], name: "index_leave_requests_on_reviewer_id"
    t.check_constraint "end_part = ANY (ARRAY[0, 1])", name: "leave_requests_valid_end_part"
    t.check_constraint "ends_on >= starts_on", name: "leave_requests_dates_in_order"
    t.check_constraint "reviewer_id IS NULL OR reviewer_id <> employee_id", name: "leave_requests_reviewer_is_not_employee"
    t.check_constraint "start_part = ANY (ARRAY[0, 1])", name: "leave_requests_valid_start_part"
    t.check_constraint "starts_on < ends_on OR start_part <= end_part", name: "leave_requests_period_boundaries_in_order"
    t.check_constraint "status = ANY (ARRAY[0, 1, 2, 3])", name: "leave_requests_valid_status"
    t.exclusion_constraint "employee_id WITH =, tsrange((starts_on +\nCASE\n    WHEN (start_part = 1) THEN 'PT12H'::interval\n    ELSE 'PT0S'::interval\nEND), (ends_on +\nCASE\n    WHEN (end_part = 0) THEN 'PT12H'::interval\n    ELSE 'P1D'::interval\nEND), '[)'::text) WITH &&", where: "status = ANY (ARRAY[0, 1])", using: :gist, name: "leave_requests_no_overlapping_active_periods"
  end

  create_table "leave_types", force: :cascade do |t|
    t.string "name", null: false
    t.string "code", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "holiday_handling", default: 0, null: false
    t.index ["code"], name: "index_leave_types_on_code", unique: true
    t.check_constraint "holiday_handling = ANY (ARRAY[0, 1])", name: "leave_types_valid_holiday_handling"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "recipient_id", null: false
    t.bigint "leave_request_event_id", null: false
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["leave_request_event_id"], name: "index_notifications_on_leave_request_event_id", unique: true
    t.index ["recipient_id"], name: "index_notifications_on_recipient_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "name", null: false
    t.integer "role", default: 0, null: false
    t.bigint "manager_id"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "password_digest", null: false
    t.date "birthday_on"
    t.index "lower((email_address)::text)", name: "index_users_on_lower_email_address", unique: true
    t.index ["manager_id"], name: "index_users_on_manager_id"
    t.check_constraint "manager_id IS NULL OR manager_id <> id", name: "users_manager_is_not_self"
    t.check_constraint "role = ANY (ARRAY[0, 1, 2])", name: "users_valid_role"
  end

  add_foreign_key "leave_request_events", "leave_requests"
  add_foreign_key "leave_request_events", "users", column: "actor_id"
  add_foreign_key "leave_requests", "leave_types"
  add_foreign_key "leave_requests", "users", column: "employee_id"
  add_foreign_key "leave_requests", "users", column: "reviewer_id"
  add_foreign_key "notifications", "leave_request_events"
  add_foreign_key "notifications", "users", column: "recipient_id"
  add_foreign_key "sessions", "users"
  add_foreign_key "users", "users", column: "manager_id"
end
