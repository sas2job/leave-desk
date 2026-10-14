class MarkAutomaticCalendarEventsAsSystem < ActiveRecord::Migration[8.1]
  def up
    change_column_null :leave_request_events, :actor_id, true
    add_check_constraint :leave_request_events, "event_type = 4 OR actor_id IS NOT NULL",
      name: "leave_request_events_actor_required_except_calendar_alert"
    execute "UPDATE leave_request_events SET actor_id = NULL WHERE event_type = 4"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Автоматические события не должны получать вымышленного автора"
  end
end
