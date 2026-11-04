class AddRegionalHolidayNotifications < ActiveRecord::Migration[8.1]
  def change
    change_column_null :notifications, :leave_request_event_id, true
    add_reference :notifications, :region, foreign_key: true
    add_column :notifications, :holiday_on, :date
    add_check_constraint :notifications, <<~SQL.squish,
      (leave_request_event_id IS NOT NULL AND region_id IS NULL AND holiday_on IS NULL) OR
      (leave_request_event_id IS NULL AND region_id IS NOT NULL AND holiday_on IS NOT NULL)
    SQL
      name: "notifications_exactly_one_source"
    add_index :notifications, [ :recipient_id, :region_id, :holiday_on ], unique: true,
      where: "region_id IS NOT NULL", name: "index_notifications_on_regional_holiday"
  end
end
