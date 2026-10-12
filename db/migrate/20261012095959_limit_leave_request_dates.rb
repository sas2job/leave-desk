class LimitLeaveRequestDates < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :leave_requests,
      "isfinite(starts_on) AND starts_on BETWEEN DATE '2000-01-01' AND DATE '2100-12-31'",
      name: "leave_requests_supported_start_date"
    add_check_constraint :leave_requests,
      "isfinite(ends_on) AND ends_on BETWEEN DATE '2000-01-01' AND DATE '2100-12-31'",
      name: "leave_requests_supported_end_date"
  end
end
