class PreventLeaveRequestSelfReview < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :leave_requests,
      "reviewer_id IS NULL OR reviewer_id <> employee_id",
      name: "leave_requests_reviewer_is_not_employee"
  end
end
