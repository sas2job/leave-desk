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

ActiveRecord::Schema[8.1].define(version: 2026_10_08_090300) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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
    t.index ["employee_id"], name: "index_leave_requests_on_employee_id"
    t.index ["leave_type_id"], name: "index_leave_requests_on_leave_type_id"
    t.index ["reviewer_id"], name: "index_leave_requests_on_reviewer_id"
    t.check_constraint "ends_on >= starts_on", name: "leave_requests_dates_in_order"
    t.check_constraint "reviewer_id IS NULL OR reviewer_id <> employee_id", name: "leave_requests_reviewer_is_not_employee"
    t.check_constraint "status = ANY (ARRAY[0, 1, 2, 3])", name: "leave_requests_valid_status"
  end

  create_table "leave_types", force: :cascade do |t|
    t.string "name", null: false
    t.string "code", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_leave_types_on_code", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "name", null: false
    t.integer "role", default: 0, null: false
    t.bigint "manager_id"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "lower((email_address)::text)", name: "index_users_on_lower_email_address", unique: true
    t.index ["manager_id"], name: "index_users_on_manager_id"
  end

  add_foreign_key "leave_requests", "leave_types"
  add_foreign_key "leave_requests", "users", column: "employee_id"
  add_foreign_key "leave_requests", "users", column: "reviewer_id"
  add_foreign_key "users", "users", column: "manager_id"
end
