class CreateLeaveRequestEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :leave_request_events do |t|
      t.references :leave_request, null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.integer :event_type, null: false
      t.integer :from_status
      t.integer :to_status, null: false
      t.text :comment
      t.datetime :occurred_at, null: false
    end
    add_check_constraint :leave_request_events, "event_type IN (0, 1, 2, 3)", name: "leave_request_events_valid_type"
    add_check_constraint :leave_request_events, "to_status IN (0, 1, 2, 3)", name: "leave_request_events_valid_to_status"
    reversible do |direction|
      direction.up do
        execute <<~SQL
          INSERT INTO leave_request_events
            (leave_request_id, actor_id, event_type, from_status, to_status, comment, occurred_at)
          SELECT id, employee_id, 0, NULL, 0, employee_comment, created_at
          FROM leave_requests
        SQL
        execute <<~SQL
          INSERT INTO leave_request_events
            (leave_request_id, actor_id, event_type, from_status, to_status, comment, occurred_at)
          SELECT id, reviewer_id, status, 0, status, review_comment, reviewed_at
          FROM leave_requests WHERE status IN (1, 2)
        SQL
        execute <<~SQL
          INSERT INTO leave_request_events
            (leave_request_id, actor_id, event_type, from_status, to_status, occurred_at)
          SELECT id, employee_id, 3, 0, 3, updated_at
          FROM leave_requests WHERE status = 3
        SQL
      end
    end
  end
end
