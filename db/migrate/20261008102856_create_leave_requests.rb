class CreateLeaveRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :leave_requests do |t|
      t.references :employee, null: false, foreign_key: { to_table: :users }
      t.references :leave_type, null: false, foreign_key: true
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.integer :status, null: false, default: 0
      t.text :employee_comment
      t.text :review_comment
      t.references :reviewer, foreign_key: { to_table: :users }
      t.datetime :reviewed_at
      t.timestamps
    end

    add_check_constraint :leave_requests, "ends_on >= starts_on",
      name: "leave_requests_dates_in_order"
    add_check_constraint :leave_requests, "status IN (0, 1, 2, 3)",
      name: "leave_requests_valid_status"
  end
end
