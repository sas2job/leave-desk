class ReplaceDayPartWithPeriodBoundaries < ActiveRecord::Migration[8.1]
  def up
    execute "ALTER TABLE leave_requests DROP CONSTRAINT leave_requests_no_overlapping_active_periods"
    add_column :leave_requests, :start_part, :integer, null: false, default: 0
    add_column :leave_requests, :end_part, :integer, null: false, default: 1
    execute <<~SQL
      UPDATE leave_requests SET
        start_part = CASE WHEN day_part = 2 THEN 1 ELSE 0 END,
        end_part = CASE WHEN day_part = 1 THEN 0 ELSE 1 END
    SQL
    remove_column :leave_requests, :day_part
    add_check_constraint :leave_requests, "start_part IN (0, 1)", name: "leave_requests_valid_start_part"
    add_check_constraint :leave_requests, "end_part IN (0, 1)", name: "leave_requests_valid_end_part"
    add_check_constraint :leave_requests,
      "starts_on < ends_on OR start_part <= end_part",
      name: "leave_requests_period_boundaries_in_order"
    add_period_exclusion_constraint
  end

  def down
    execute "ALTER TABLE leave_requests DROP CONSTRAINT leave_requests_no_overlapping_active_periods"
    add_column :leave_requests, :day_part, :integer, null: false, default: 0
    execute <<~SQL
      UPDATE leave_requests SET day_part = CASE
        WHEN starts_on = ends_on AND start_part = 0 AND end_part = 0 THEN 1
        WHEN starts_on = ends_on AND start_part = 1 AND end_part = 1 THEN 2
        ELSE 0
      END
    SQL
    remove_column :leave_requests, :start_part
    remove_column :leave_requests, :end_part
    add_check_constraint :leave_requests, "day_part IN (0, 1, 2)", name: "leave_requests_valid_day_part"
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
      ) WHERE (status IN (0, 1))
    SQL
  end

  private

  def add_period_exclusion_constraint
    execute <<~SQL
      ALTER TABLE leave_requests
      ADD CONSTRAINT leave_requests_no_overlapping_active_periods
      EXCLUDE USING gist (
        employee_id WITH =,
        tsrange(
          starts_on + CASE WHEN start_part = 1 THEN interval '12 hours' ELSE interval '0 hours' END,
          ends_on + CASE WHEN end_part = 0 THEN interval '12 hours' ELSE interval '1 day' END,
          '[)'
        ) WITH &&
      ) WHERE (status IN (0, 1))
    SQL
  end
end
