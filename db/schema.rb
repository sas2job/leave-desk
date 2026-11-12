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

ActiveRecord::Schema[8.1].define(version: 2026_11_12_000003) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "btree_gist"
  enable_extension "pg_catalog.plpgsql"

  create_table "annual_leave_adjustments", force: :cascade do |t|
    t.bigint "annual_leave_year_id", null: false
    t.bigint "actor_id", null: false
    t.integer "previous_entitlement_days", null: false
    t.integer "entitlement_days", null: false
    t.bigint "previous_opening_used_minutes", null: false
    t.bigint "opening_used_minutes", null: false
    t.string "reason", limit: 200, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_annual_leave_adjustments_on_actor_id"
    t.index ["annual_leave_year_id"], name: "index_annual_leave_adjustments_on_annual_leave_year_id"
  end

  create_table "annual_leave_bookings", force: :cascade do |t|
    t.bigint "leave_request_id", null: false
    t.bigint "annual_leave_year_id", null: false
    t.bigint "minutes", null: false
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["annual_leave_year_id"], name: "index_annual_leave_bookings_on_annual_leave_year_id"
    t.index ["leave_request_id", "annual_leave_year_id"], name: "annual_leave_booking_per_year", unique: true
    t.index ["leave_request_id"], name: "index_annual_leave_bookings_on_leave_request_id"
    t.check_constraint "minutes >= 0 AND (status = ANY (ARRAY[0, 1, 2]))", name: "annual_leave_bookings_amount"
  end

  create_table "annual_leave_years", force: :cascade do |t|
    t.bigint "employee_id", null: false
    t.bigint "recorded_by_id", null: false
    t.date "starts_on", null: false
    t.date "ends_on", null: false
    t.integer "entitlement_days", null: false
    t.bigint "opening_used_minutes", default: 0, null: false
    t.bigint "reserved_minutes", default: 0, null: false
    t.bigint "committed_minutes", default: 0, null: false
    t.string "basis", limit: 200, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["employee_id"], name: "index_annual_leave_years_on_employee_id"
    t.index ["recorded_by_id"], name: "index_annual_leave_years_on_recorded_by_id"
    t.check_constraint "entitlement_days >= 28 AND opening_used_minutes >= 0 AND reserved_minutes >= 0 AND committed_minutes >= 0 AND (opening_used_minutes + reserved_minutes + committed_minutes) <= (entitlement_days::bigint * 1440)", name: "annual_leave_years_capacity"
    t.check_constraint "isfinite(starts_on) AND isfinite(ends_on) AND starts_on >= '2000-01-01'::date AND ends_on <= '2100-12-31'::date AND ends_on > starts_on", name: "annual_leave_years_dates"
    t.exclusion_constraint "employee_id WITH =, daterange(starts_on, ends_on, '[]'::text) WITH &&", using: :gist, name: "annual_leave_years_no_overlap"
  end

  create_table "demo_seed_archives", force: :cascade do |t|
    t.string "plan_digest", limit: 64, null: false
    t.jsonb "archived_data", null: false
    t.jsonb "summary", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["plan_digest"], name: "index_demo_seed_archives_on_plan_digest", unique: true
  end

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

  create_table "leave_legal_reviews", force: :cascade do |t|
    t.bigint "leave_request_id", null: false
    t.bigint "reviewer_id", null: false
    t.boolean "annual", default: false, null: false
    t.boolean "conditions_confirmed", default: false, null: false
    t.boolean "age_boundary_confirmed", default: false, null: false
    t.text "document_reference"
    t.date "document_starts_on"
    t.date "document_ends_on"
    t.date "working_year_starts_on"
    t.date "working_year_ends_on"
    t.integer "entitlement_days"
    t.datetime "confirmed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["leave_request_id"], name: "index_leave_legal_reviews_on_leave_request_id", unique: true
    t.index ["reviewer_id"], name: "index_leave_legal_reviews_on_reviewer_id"
    t.check_constraint "annual AND working_year_starts_on IS NOT NULL AND working_year_ends_on IS NOT NULL AND isfinite(working_year_starts_on) AND isfinite(working_year_ends_on) AND working_year_ends_on >= working_year_starts_on AND entitlement_days IS NOT NULL AND entitlement_days >= 28 OR NOT annual AND document_reference IS NOT NULL AND length(btrim(document_reference)) > 0", name: "leave_legal_reviews_basis_required"
    t.check_constraint "conditions_confirmed", name: "leave_legal_reviews_confirmed"
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
    t.check_constraint "event_type >= 0 AND event_type <= 18", name: "leave_request_events_valid_type"
    t.check_constraint "to_status = ANY (ARRAY[0, 1, 2, 3, 4, 5])", name: "leave_request_events_valid_to_status"
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
    t.integer "legal_kind", default: 0, null: false
    t.date "child_born_on"
    t.integer "care_relationship"
    t.date "returned_on"
    t.integer "birthday_claim_year"
    t.boolean "birthday_used", default: false, null: false
    t.bigint "resumes_request_id"
    t.date "sick_closed_on"
    t.datetime "sick_closed_at"
    t.bigint "annual_cancelled_used_minutes", default: 0, null: false
    t.index ["employee_id", "birthday_claim_year"], name: "leave_requests_one_birthday_per_year", unique: true, where: "((birthday_claim_year IS NOT NULL) AND ((status = ANY (ARRAY[0, 1])) OR birthday_used))"
    t.index ["employee_id", "id"], name: "index_leave_requests_on_employee_id_and_id"
    t.index ["employee_id"], name: "index_leave_requests_on_employee_id"
    t.index ["leave_type_id"], name: "index_leave_requests_on_leave_type_id"
    t.index ["region_id"], name: "index_leave_requests_on_region_id"
    t.index ["resumes_request_id"], name: "index_leave_requests_on_resumes_request_id"
    t.index ["reviewer_id"], name: "index_leave_requests_on_reviewer_id"
    t.check_constraint "annual_cancelled_used_minutes >= 0", name: "leave_requests_annual_cancelled_usage"
    t.check_constraint "birthday_claim_year IS NULL OR birthday_claim_year = EXTRACT(year FROM starts_on)::integer", name: "leave_requests_birthday_claim_year"
    t.check_constraint "duration_half_days > 0 AND duration_minutes IS NULL OR duration_minutes > 0 AND duration_half_days IS NULL", name: "leave_requests_positive_duration"
    t.check_constraint "end_minute >= 1 AND end_minute <= 1440", name: "leave_requests_valid_end_minute"
    t.check_constraint "end_part = ANY (ARRAY[0, 1])", name: "leave_requests_valid_end_part"
    t.check_constraint "ends_on >= starts_on", name: "leave_requests_dates_in_order"
    t.check_constraint "isfinite(ends_on) AND ends_on >= '2000-01-01'::date AND ends_on <= '2100-12-31'::date", name: "leave_requests_supported_end_date"
    t.check_constraint "isfinite(starts_on) AND starts_on >= '2000-01-01'::date AND starts_on <= '2100-12-31'::date", name: "leave_requests_supported_start_date"
    t.check_constraint "legal_kind <> 3 OR child_born_on IS NOT NULL AND isfinite(child_born_on) AND child_born_on >= '2000-01-01'::date AND child_born_on <= '2100-12-31'::date AND starts_on >= child_born_on AND ends_on <= (child_born_on + 'P3Y'::interval +\nCASE\n    WHEN to_char(child_born_on::timestamp with time zone, 'MM-DD'::text) = '02-29'::text THEN 'P1D'::interval\n    ELSE 'PT0S'::interval\nEND)::date AND care_relationship IS NOT NULL AND (care_relationship = ANY (ARRAY[0, 1, 2, 3, 4]))", name: "leave_requests_childcare_period"
    t.check_constraint "legal_kind <> 4 OR starts_on = ends_on AND birthday_claim_year IS NOT NULL", name: "leave_requests_birthday_one_day"
    t.check_constraint "legal_kind = 0 OR start_minute IS NOT NULL AND end_minute IS NOT NULL AND start_minute = 0 AND end_minute = 1440", name: "leave_requests_statutory_full_days"
    t.check_constraint "legal_kind = ANY (ARRAY[0, 1, 2, 3, 4, 5])", name: "leave_requests_valid_legal_kind"
    t.check_constraint "resumes_request_id IS NULL OR resumes_request_id <> id", name: "leave_requests_resume_not_self"
    t.check_constraint "reviewer_id IS NULL OR reviewer_id <> employee_id", name: "leave_requests_reviewer_is_not_employee"
    t.check_constraint "sick_closed_on IS NULL AND sick_closed_at IS NULL OR sick_closed_on IS NOT NULL AND sick_closed_at IS NOT NULL AND status = 1 AND isfinite(sick_closed_on) AND sick_closed_on = ends_on", name: "leave_requests_sick_closure"
    t.check_constraint "start_minute >= 0 AND start_minute <= 1439", name: "leave_requests_valid_start_minute"
    t.check_constraint "start_minute IS NULL AND end_minute IS NULL AND duration_minutes IS NULL AND duration_half_days IS NOT NULL OR start_minute IS NOT NULL AND end_minute IS NOT NULL AND duration_minutes IS NOT NULL AND duration_half_days IS NULL", name: "leave_requests_consistent_time_precision"
    t.check_constraint "start_part = ANY (ARRAY[0, 1])", name: "leave_requests_valid_start_part"
    t.check_constraint "starts_on < ends_on OR start_minute IS NULL AND start_part <= end_part OR start_minute IS NOT NULL AND start_minute < end_minute", name: "leave_requests_period_boundaries_in_order"
    t.check_constraint "status = 4 AND recalled_on IS NOT NULL AND isfinite(recalled_on) AND recalled_on > starts_on AND recalled_on <= ends_on OR status <> 4 AND recalled_on IS NULL", name: "leave_requests_recall_date"
    t.check_constraint "status = 5 AND legal_kind = 3 AND returned_on IS NOT NULL AND isfinite(returned_on) AND returned_on >= starts_on AND returned_on <= ends_on OR status <> 5 AND returned_on IS NULL", name: "leave_requests_childcare_return"
    t.check_constraint "status = ANY (ARRAY[0, 1, 2, 3, 4, 5])", name: "leave_requests_valid_status"
    t.exclusion_constraint "employee_id WITH =, tsrange((starts_on + ((COALESCE(start_minute, (start_part * 720)))::double precision * 'PT1M'::interval)),\nCASE\n    WHEN (COALESCE(recalled_on, returned_on) IS NOT NULL) THEN (COALESCE(recalled_on, returned_on))::timestamp without time zone\n    ELSE (ends_on + ((COALESCE(end_minute, ((end_part + 1) * 720)))::double precision * 'PT1M'::interval))\nEND, '[)'::text) WITH &&", where: "status = ANY (ARRAY[0, 1, 4, 5])", using: :gist, name: "leave_requests_no_overlapping_active_periods"
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

  create_table "sick_leave_extensions", force: :cascade do |t|
    t.bigint "leave_request_id", null: false
    t.bigint "requested_by_id", null: false
    t.bigint "reviewer_id"
    t.date "previous_ends_on", null: false
    t.date "proposed_ends_on", null: false
    t.integer "status", default: 0, null: false
    t.datetime "reviewed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["leave_request_id"], name: "index_sick_leave_extensions_on_leave_request_id"
    t.index ["leave_request_id"], name: "one_pending_sick_extension", unique: true, where: "(status = 0)"
    t.index ["requested_by_id"], name: "index_sick_leave_extensions_on_requested_by_id"
    t.index ["reviewer_id"], name: "index_sick_leave_extensions_on_reviewer_id"
    t.check_constraint "(status = ANY (ARRAY[0, 3])) AND reviewer_id IS NULL AND reviewed_at IS NULL OR (status = ANY (ARRAY[1, 2])) AND reviewer_id IS NOT NULL AND reviewer_id <> requested_by_id AND reviewed_at IS NOT NULL", name: "sick_extensions_review_details"
    t.check_constraint "isfinite(previous_ends_on) AND isfinite(proposed_ends_on) AND proposed_ends_on > previous_ends_on AND previous_ends_on >= '2000-01-01'::date AND proposed_ends_on <= '2100-12-31'::date", name: "sick_extensions_supported_period"
    t.check_constraint "status = ANY (ARRAY[0, 1, 2, 3])", name: "sick_extensions_valid_status"
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
    t.boolean "extended_annual_leave", default: false, null: false
    t.integer "annual_base_days", default: 28, null: false
    t.integer "annual_additional_days", default: 0, null: false
    t.string "annual_leave_basis", limit: 200
    t.index "lower((email_address)::text)", name: "index_users_on_lower_email_address", unique: true
    t.index ["manager_id"], name: "index_users_on_manager_id"
    t.index ["region_id"], name: "index_users_on_region_id"
    t.check_constraint "annual_base_days >= 28 AND annual_additional_days >= 0", name: "users_annual_entitlement"
    t.check_constraint "birthday_on IS NULL OR isfinite(birthday_on)", name: "users_finite_birthday"
    t.check_constraint "manager_id IS NULL OR manager_id <> id", name: "users_manager_is_not_self"
    t.check_constraint "role = ANY (ARRAY[0, 1, 2])", name: "users_valid_role"
  end

  add_foreign_key "annual_leave_adjustments", "annual_leave_years"
  add_foreign_key "annual_leave_adjustments", "users", column: "actor_id"
  add_foreign_key "annual_leave_bookings", "annual_leave_years"
  add_foreign_key "annual_leave_bookings", "leave_requests"
  add_foreign_key "annual_leave_years", "users", column: "employee_id"
  add_foreign_key "annual_leave_years", "users", column: "recorded_by_id"
  add_foreign_key "leave_legal_reviews", "leave_requests"
  add_foreign_key "leave_legal_reviews", "users", column: "reviewer_id"
  add_foreign_key "leave_recalls", "leave_requests"
  add_foreign_key "leave_recalls", "users", column: "confirmed_by_id"
  add_foreign_key "leave_recalls", "users", column: "requested_by_id"
  add_foreign_key "leave_request_events", "leave_requests"
  add_foreign_key "leave_request_events", "users", column: "actor_id"
  add_foreign_key "leave_requests", "leave_requests", column: "resumes_request_id"
  add_foreign_key "leave_requests", "leave_types"
  add_foreign_key "leave_requests", "regions"
  add_foreign_key "leave_requests", "users", column: "employee_id"
  add_foreign_key "leave_requests", "users", column: "reviewer_id"
  add_foreign_key "notifications", "leave_request_events"
  add_foreign_key "notifications", "regions"
  add_foreign_key "notifications", "users", column: "recipient_id"
  add_foreign_key "regional_calendars", "regions"
  add_foreign_key "sessions", "users"
  add_foreign_key "sick_leave_extensions", "leave_requests"
  add_foreign_key "sick_leave_extensions", "users", column: "requested_by_id"
  add_foreign_key "sick_leave_extensions", "users", column: "reviewer_id"
  add_foreign_key "users", "regions"
  add_foreign_key "users", "users", column: "manager_id"
end
