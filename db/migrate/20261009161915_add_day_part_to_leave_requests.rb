class AddDayPartToLeaveRequests < ActiveRecord::Migration[8.1]
  def up
    execute "ALTER TABLE leave_requests DROP CONSTRAINT leave_requests_no_overlapping_active_periods"
    add_column :leave_requests, :day_part, :integer, null: false, default: 0
    add_check_constraint :leave_requests, "day_part IN (0, 1, 2)",
      name: "leave_requests_valid_day_part"
    add_check_constraint :leave_requests, "day_part = 0 OR starts_on = ends_on",
      name: "leave_requests_partial_day_is_single_day"

    execute <<~SQL
      ALTER TABLE leave_requests
      ADD CONSTRAINT leave_requests_no_overlapping_active_periods
      EXCLUDE USING gist (
        employee_id WITH =,
        tsrange(
          starts_on + CASE WHEN day_part = 2 THEN interval '12 hours' ELSE interval '0 hours' END,
          ends_on + CASE WHEN day_part = 1 THEN interval '12 hours' ELSE interval '1 day' END,
          '[)'
        ) WITH &&
      )
      WHERE (status IN (0, 1))
    SQL
  end

  def down
    execute "ALTER TABLE leave_requests DROP CONSTRAINT leave_requests_no_overlapping_active_periods"
    remove_column :leave_requests, :day_part
    execute <<~SQL
      ALTER TABLE leave_requests
      ADD CONSTRAINT leave_requests_no_overlapping_active_periods
      EXCLUDE USING gist (
        employee_id WITH =,
        daterange(starts_on, ends_on, '[]') WITH &&
      )
      WHERE (status IN (0, 1))
    SQL
  end
end
