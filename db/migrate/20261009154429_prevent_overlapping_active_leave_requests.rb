class PreventOverlappingActiveLeaveRequests < ActiveRecord::Migration[8.1]
  def up
    enable_extension "btree_gist"

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

  def down
    execute <<~SQL
      ALTER TABLE leave_requests
      DROP CONSTRAINT leave_requests_no_overlapping_active_periods
    SQL
  end
end
