class RecordPreciseLeaveTimes < ActiveRecord::Migration[8.1]
  def up
    add_column :leave_requests, :start_minute, :integer
    add_column :leave_requests, :end_minute, :integer
    add_column :leave_requests, :duration_minutes, :integer
    change_column_null :leave_requests, :duration_half_days, true

    remove_check_constraint :leave_requests, name: "leave_requests_positive_duration"
    remove_check_constraint :leave_requests, name: "leave_requests_period_boundaries_in_order"
    execute "ALTER TABLE leave_requests DROP CONSTRAINT leave_requests_no_overlapping_active_periods"

    add_check_constraint :leave_requests,
      "(start_minute IS NULL AND end_minute IS NULL AND duration_minutes IS NULL AND duration_half_days IS NOT NULL) OR " \
      "(start_minute IS NOT NULL AND end_minute IS NOT NULL AND duration_minutes IS NOT NULL AND duration_half_days IS NULL)",
      name: "leave_requests_consistent_time_precision"
    add_check_constraint :leave_requests, "start_minute BETWEEN 0 AND 1439", name: "leave_requests_valid_start_minute"
    add_check_constraint :leave_requests, "end_minute BETWEEN 1 AND 1440", name: "leave_requests_valid_end_minute"
    add_check_constraint :leave_requests, "duration_half_days > 0 AND duration_minutes IS NULL OR duration_minutes > 0 AND duration_half_days IS NULL",
      name: "leave_requests_positive_duration"
    add_check_constraint :leave_requests,
      "starts_on < ends_on OR (start_minute IS NULL AND start_part <= end_part) OR " \
      "(start_minute IS NOT NULL AND start_minute < end_minute)",
      name: "leave_requests_period_boundaries_in_order"

    execute <<~SQL
      ALTER TABLE leave_requests
      ADD CONSTRAINT leave_requests_no_overlapping_active_periods
      EXCLUDE USING gist (
        employee_id WITH =,
        tsrange(
          starts_on + (COALESCE(start_minute, start_part * 720) * interval '1 minute'),
          ends_on + (COALESCE(end_minute, (end_part + 1) * 720) * interval '1 minute'),
          '[)'
        ) WITH &&
      ) WHERE (status IN (0, 1))
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Precise leave times cannot be represented as half days"
  end
end
