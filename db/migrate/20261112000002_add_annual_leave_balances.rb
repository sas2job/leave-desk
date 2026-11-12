class AddAnnualLeaveBalances < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :extended_annual_leave, :boolean, null: false, default: false
    add_column :users, :annual_base_days, :integer, null: false, default: 28
    add_column :users, :annual_additional_days, :integer, null: false, default: 0
    add_column :users, :annual_leave_basis, :string, limit: 200
    add_check_constraint :users, "annual_base_days >= 28 AND annual_additional_days >= 0", name: "users_annual_entitlement"
    add_column :leave_requests, :annual_cancelled_used_minutes, :bigint, null: false, default: 0
    add_check_constraint :leave_requests, "annual_cancelled_used_minutes >= 0", name: "leave_requests_annual_cancelled_usage"

    create_table :annual_leave_years do |t|
      t.references :employee, null: false, foreign_key: { to_table: :users }
      t.references :recorded_by, null: false, foreign_key: { to_table: :users }
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.integer :entitlement_days, null: false
      t.bigint :opening_used_minutes, null: false, default: 0
      t.bigint :reserved_minutes, null: false, default: 0
      t.bigint :committed_minutes, null: false, default: 0
      t.string :basis, null: false, limit: 200
      t.timestamps
    end
    add_check_constraint :annual_leave_years,
      "isfinite(starts_on) AND isfinite(ends_on) AND starts_on >= DATE '2000-01-01' " \
      "AND ends_on <= DATE '2100-12-31' AND ends_on > starts_on", name: "annual_leave_years_dates"
    add_check_constraint :annual_leave_years,
      "entitlement_days >= 28 AND opening_used_minutes >= 0 AND reserved_minutes >= 0 AND committed_minutes >= 0 " \
      "AND opening_used_minutes + reserved_minutes + committed_minutes <= entitlement_days::bigint * 1440",
      name: "annual_leave_years_capacity"
    add_exclusion_constraint :annual_leave_years,
      "employee_id WITH =, daterange(starts_on, ends_on, '[]') WITH &&", using: :gist, name: "annual_leave_years_no_overlap"

    create_table :annual_leave_bookings do |t|
      t.references :leave_request, null: false, foreign_key: true
      t.references :annual_leave_year, null: false, foreign_key: true
      t.bigint :minutes, null: false
      t.integer :status, null: false, default: 0
      t.timestamps
    end
    add_index :annual_leave_bookings, [ :leave_request_id, :annual_leave_year_id ], unique: true, name: "annual_leave_booking_per_year"
    add_check_constraint :annual_leave_bookings, "minutes >= 0 AND status IN (0, 1, 2)", name: "annual_leave_bookings_amount"
    create_table :annual_leave_adjustments do |t|
      t.references :annual_leave_year, null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.integer :previous_entitlement_days, null: false
      t.integer :entitlement_days, null: false
      t.bigint :previous_opening_used_minutes, null: false
      t.bigint :opening_used_minutes, null: false
      t.string :reason, null: false, limit: 200
      t.timestamps
    end
  end
end
