class AddInternalSickLeaveTracking < ActiveRecord::Migration[8.1]
  def change
    add_column :leave_requests, :sick_closed_on, :date
    add_column :leave_requests, :sick_closed_at, :datetime
    remove_check_constraint :leave_requests, name: "leave_requests_valid_legal_kind", expression: "legal_kind IN (0, 1, 2, 3, 4)"
    add_check_constraint :leave_requests, "legal_kind IN (0, 1, 2, 3, 4, 5)", name: "leave_requests_valid_legal_kind"
    add_check_constraint :leave_requests,
      "(sick_closed_on IS NULL AND sick_closed_at IS NULL) OR " \
      "(sick_closed_on IS NOT NULL AND sick_closed_at IS NOT NULL AND status = 1 AND " \
      "isfinite(sick_closed_on) AND sick_closed_on = ends_on)", name: "leave_requests_sick_closure"

    create_table :sick_leave_extensions do |t|
      t.references :leave_request, null: false, foreign_key: true
      t.references :requested_by, null: false, foreign_key: { to_table: :users }
      t.references :reviewer, foreign_key: { to_table: :users }
      t.date :previous_ends_on, null: false
      t.date :proposed_ends_on, null: false
      t.integer :status, null: false, default: 0
      t.datetime :reviewed_at
      t.timestamps
    end
    add_index :sick_leave_extensions, :leave_request_id, unique: true, where: "status = 0", name: "one_pending_sick_extension"
    add_check_constraint :sick_leave_extensions,
      "isfinite(previous_ends_on) AND isfinite(proposed_ends_on) AND proposed_ends_on > previous_ends_on " \
      "AND previous_ends_on >= DATE '2000-01-01' AND proposed_ends_on <= DATE '2100-12-31'",
      name: "sick_extensions_supported_period"
    add_check_constraint :sick_leave_extensions, "status IN (0, 1, 2, 3)", name: "sick_extensions_valid_status"
    add_check_constraint :sick_leave_extensions,
      "(status IN (0, 3) AND reviewer_id IS NULL AND reviewed_at IS NULL) OR " \
      "(status IN (1, 2) AND reviewer_id IS NOT NULL AND reviewer_id <> requested_by_id AND reviewed_at IS NOT NULL)",
      name: "sick_extensions_review_details"
    remove_check_constraint :leave_request_events, name: "leave_request_events_valid_type", expression: "event_type BETWEEN 0 AND 13"
    add_check_constraint :leave_request_events, "event_type BETWEEN 0 AND 18", name: "leave_request_events_valid_type"
  end
end
