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

ActiveRecord::Schema[8.1].define(version: 2026_11_06_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "btree_gist"
  enable_extension "pg_catalog.plpgsql"

  create_table "federal_calendars", force: :cascade do |t|
    t.integer "year", null: false
    t.text "legal_basis", null: false
    t.date "public_holidays", default: [], null: false, array: true
    t.jsonb "transfers", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["year"], name: "index_federal_calendars_on_year", unique: true
    t.check_constraint "jsonb_typeof(transfers) = 'array'::text", name: "federal_calendars_transfers_array"
    t.check_constraint "year >= 2000 AND year <= 2100", name: "federal_calendars_supported_year"
  end

  create_table "leave_recalls", force: :cascade do |t|
    t.bigint "leave_request_id", null: false
    t.bigint "requested_by_id", null: false
    t.date "return_on", null: false
    t.text "reason", null: false
    t.boolean "eligibility_confirmed", default: false, null: false
    t.integer "status", default: 0, null: false
    t.datetime "responded_at"
    t.integer "remainder_option"
    t.text "remainder_preference"
    t.bigint "confirmed_by_id"
    t.datetime "confirmed_at"
    t.string "order_number", limit: 100
    t.string "consent_reference", limit: 200
    t.date "order_on"
    t.integer "unused_days"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["confirmed_by_id"], name: "index_leave_recalls_on_confirmed_by_id"
    t.index ["leave_request_id"], name: "index_leave_recalls_on_leave_request_id"
    t.index ["leave_request_id"], name: "leave_recalls_one_confirmation_per_request", unique: true, where: "(status = 4)"
    t.index ["leave_request_id"], name: "leave_recalls_one_open_per_request", unique: true, where: "(status = ANY (ARRAY[0, 1]))"
    t.index ["requested_by_id"], name: "index_leave_recalls_on_requested_by_id"
    t.check_constraint "(status <> ALL (ARRAY[1, 4])) OR responded_at IS NOT NULL AND remainder_option IS NOT NULL", name: "leave_recalls_consent_required"
    t.check_constraint "eligibility_confirmed", name: "leave_recalls_eligibility_confirmed"
    t.check_constraint "isfinite(return_on) AND return_on >= '2000-01-01'::date AND return_on <= '2100-12-31'::date", name: "leave_recalls_supported_return_date"
    t.check_constraint "remainder_option IS NULL OR (remainder_option = ANY (ARRAY[0, 1]))", name: "leave_recalls_valid_remainder_option"
    t.check_constraint "status <> 2 OR responded_at IS NOT NULL", name: "leave_recalls_decline_recorded"
    t.check_constraint "status = 4 AND confirmed_by_id IS NOT NULL AND confirmed_at IS NOT NULL AND order_number IS NOT NULL AND length(btrim(order_number::text)) > 0 AND consent_reference IS NOT NULL AND length(btrim(consent_reference::text)) > 0 AND order_on IS NOT NULL AND isfinite(order_on) AND order_on < return_on AND unused_days > 0 AND unused_days IS NOT NULL OR status <> 4 AND confirmed_by_id IS NULL AND confirmed_at IS NULL AND order_number IS NULL AND consent_reference IS NULL AND order_on IS NULL AND unused_days IS NULL", name: "leave_recalls_confirmation_complete"
    t.check_constraint "status = ANY (ARRAY[0, 1, 2, 3, 4])", name: "leave_recalls_valid_status"
  end

  create_table "leave_request_events", force: :cascade do |t|
    t.bigint "leave_request_id", null: false
    t.bigint "actor_id"
    t.integer "event_type", null: false
    t.integer "from_status"
    t.integer "to_status", null: false
    t.text "comment"
    t.datetime "occurred_at", null: false
    t.index ["actor_id"], name: "index_leave_request_events_on_actor_id"
    t.index ["leave_request_id"], name: "index_leave_request_events_on_leave_request_id"
    t.check_constraint "event_type = 4 OR actor_id IS NOT NULL", name: "leave_request_events_actor_required_except_calendar_alert"
    t.check_constraint "event_type >= 0 AND event_type <= 10", name: "leave_request_events_valid_type"
    t.check_constraint "to_status = ANY (ARRAY[0, 1, 2, 3, 4])", name: "leave_request_events_valid_to_status"
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
    t.integer "duration_half_days"
    t.boolean "calendar_unverified", default: false, null: false
    t.integer "start_minute"
    t.integer "end_minute"
    t.integer "duration_minutes"
    t.bigint "region_id"
    t.date "recalled_on"
    t.index ["employee_id", "id"], name: "index_leave_requests_on_employee_id_and_id"
    t.index ["employee_id"], name: "index_leave_requests_on_employee_id"
    t.index ["leave_type_id"], name: "index_leave_requests_on_leave_type_id"
    t.index ["region_id"], name: "index_leave_requests_on_region_id"
    t.index ["reviewer_id"], name: "index_leave_requests_on_reviewer_id"
    t.check_constraint "duration_half_days > 0 AND duration_minutes IS NULL OR duration_minutes > 0 AND duration_half_days IS NULL", name: "leave_requests_positive_duration"
    t.check_constraint "end_minute >= 1 AND end_minute <= 1440", name: "leave_requests_valid_end_minute"
    t.check_constraint "end_part = ANY (ARRAY[0, 1])", name: "leave_requests_valid_end_part"
    t.check_constraint "ends_on >= starts_on", name: "leave_requests_dates_in_order"
    t.check_constraint "isfinite(ends_on) AND ends_on >= '2000-01-01'::date AND ends_on <= '2100-12-31'::date", name: "leave_requests_supported_end_date"
    t.check_constraint "isfinite(starts_on) AND starts_on >= '2000-01-01'::date AND starts_on <= '2100-12-31'::date", name: "leave_requests_supported_start_date"
    t.check_constraint "reviewer_id IS NULL OR reviewer_id <> employee_id", name: "leave_requests_reviewer_is_not_employee"
    t.check_constraint "start_minute >= 0 AND start_minute <= 1439", name: "leave_requests_valid_start_minute"
    t.check_constraint "start_minute IS NULL AND end_minute IS NULL AND duration_minutes IS NULL AND duration_half_days IS NOT NULL OR start_minute IS NOT NULL AND end_minute IS NOT NULL AND duration_minutes IS NOT NULL AND duration_half_days IS NULL", name: "leave_requests_consistent_time_precision"
    t.check_constraint "start_part = ANY (ARRAY[0, 1])", name: "leave_requests_valid_start_part"
    t.check_constraint "starts_on < ends_on OR start_minute IS NULL AND start_part <= end_part OR start_minute IS NOT NULL AND start_minute < end_minute", name: "leave_requests_period_boundaries_in_order"
    t.check_constraint "status = 4 AND recalled_on IS NOT NULL AND isfinite(recalled_on) AND recalled_on > starts_on AND recalled_on <= ends_on OR status <> 4 AND recalled_on IS NULL", name: "leave_requests_recall_date"
    t.check_constraint "status = ANY (ARRAY[0, 1, 2, 3, 4])", name: "leave_requests_valid_status"
    t.exclusion_constraint "employee_id WITH =, tsrange((starts_on + ((COALESCE(start_minute, (start_part * 720)))::double precision * 'PT1M'::interval)),\nCASE\n    WHEN (recalled_on IS NOT NULL) THEN (recalled_on)::timestamp without time zone\n    ELSE (ends_on + ((COALESCE(end_minute, ((end_part + 1) * 720)))::double precision * 'PT1M'::interval))\nEND, '[)'::text) WITH &&", where: "status = ANY (ARRAY[0, 1, 4])", using: :gist, name: "leave_requests_no_overlapping_active_periods"
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
    t.bigint "leave_request_event_id"
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "region_id"
    t.date "holiday_on"
    t.index ["leave_request_event_id", "recipient_id"], name: "index_notifications_on_event_and_recipient", unique: true
    t.index ["recipient_id", "id"], name: "index_notifications_on_recipient_id_and_id"
    t.index ["recipient_id", "region_id", "holiday_on"], name: "index_notifications_on_regional_holiday", unique: true, where: "(region_id IS NOT NULL)"
    t.index ["recipient_id"], name: "index_notifications_on_recipient_id"
    t.index ["region_id"], name: "index_notifications_on_region_id"
    t.check_constraint "leave_request_event_id IS NOT NULL AND region_id IS NULL AND holiday_on IS NULL OR leave_request_event_id IS NULL AND region_id IS NOT NULL AND holiday_on IS NOT NULL", name: "notifications_exactly_one_source"
  end

  create_table "regional_calendars", force: :cascade do |t|
    t.bigint "region_id", null: false
    t.integer "year", null: false
    t.text "legal_basis", null: false
    t.date "public_holidays", default: [], null: false, array: true
    t.date "additional_days_off", default: [], null: false, array: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "complete", default: false, null: false
    t.index ["region_id", "year"], name: "index_regional_calendars_on_region_id_and_year", unique: true
    t.index ["region_id"], name: "index_regional_calendars_on_region_id"
    t.check_constraint "year >= 2000 AND year <= 2100", name: "regional_calendars_supported_year"
  end

  create_table "regions", force: :cascade do |t|
    t.string "code", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_regions_on_code", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_sessions_on_created_at"
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
    t.string "city"
    t.string "time_zone", default: "Europe/Moscow", null: false
    t.bigint "region_id"
    t.index "lower((email_address)::text)", name: "index_users_on_lower_email_address", unique: true
    t.index ["manager_id"], name: "index_users_on_manager_id"
    t.index ["region_id"], name: "index_users_on_region_id"
    t.check_constraint "birthday_on IS NULL OR isfinite(birthday_on)", name: "users_finite_birthday"
    t.check_constraint "manager_id IS NULL OR manager_id <> id", name: "users_manager_is_not_self"
    t.check_constraint "role = ANY (ARRAY[0, 1, 2])", name: "users_valid_role"
  end

  add_foreign_key "leave_recalls", "leave_requests"
  add_foreign_key "leave_recalls", "users", column: "confirmed_by_id"
  add_foreign_key "leave_recalls", "users", column: "requested_by_id"
  add_foreign_key "leave_request_events", "leave_requests"
  add_foreign_key "leave_request_events", "users", column: "actor_id"
  add_foreign_key "leave_requests", "leave_types"
  add_foreign_key "leave_requests", "regions"
  add_foreign_key "leave_requests", "users", column: "employee_id"
  add_foreign_key "leave_requests", "users", column: "reviewer_id"
  add_foreign_key "notifications", "leave_request_events"
  add_foreign_key "notifications", "regions"
  add_foreign_key "notifications", "users", column: "recipient_id"
  add_foreign_key "regional_calendars", "regions"
  add_foreign_key "sessions", "users"
  add_foreign_key "users", "regions"
  add_foreign_key "users", "users", column: "manager_id"
end
