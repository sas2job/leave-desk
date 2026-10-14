class FlagRequestsWithoutFederalCalendar < ActiveRecord::Migration[8.1]
  def up
    add_column :leave_requests, :calendar_unverified, :boolean, default: false, null: false
    remove_check_constraint :leave_request_events, name: "leave_request_events_valid_type"
    add_check_constraint :leave_request_events, "event_type = ANY (ARRAY[0, 1, 2, 3, 4, 5])",
      name: "leave_request_events_valid_type"
    remove_index :notifications, :leave_request_event_id
    add_index :notifications, %i[leave_request_event_id recipient_id], unique: true,
      name: "index_notifications_on_event_and_recipient"

    current_year = Date.current.year
    execute <<~SQL
      UPDATE leave_requests AS requests
      SET calendar_unverified = TRUE
      WHERE requests.status IN (0, 1)
        AND EXTRACT(YEAR FROM requests.starts_on) = #{current_year}
        AND NOT EXISTS (
          SELECT 1 FROM federal_calendars WHERE year = #{current_year}
        )
    SQL
    execute <<~SQL
      INSERT INTO leave_request_events
        (leave_request_id, actor_id, event_type, to_status, comment, occurred_at)
      SELECT requests.id, requests.employee_id, 4, requests.status,
        'Календарь года не был внесён при создании заявки', CURRENT_TIMESTAMP
      FROM leave_requests requests
      WHERE requests.calendar_unverified = TRUE
        AND NOT EXISTS (
          SELECT 1 FROM leave_request_events events
          WHERE events.leave_request_id = requests.id AND events.event_type = 4
        )
    SQL
    execute <<~SQL
      INSERT INTO notifications
        (recipient_id, leave_request_event_id, created_at, updated_at)
      SELECT administrators.id, events.id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM leave_request_events events
      CROSS JOIN users administrators
      WHERE events.event_type = 4
        AND administrators.role = 2 AND administrators.active = TRUE
      ON CONFLICT DO NOTHING
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "События проверки календаря нельзя удалять из истории"
  end
end
