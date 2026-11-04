class AddRegionalCalendarCompleteness < ActiveRecord::Migration[8.1]
  def change
    add_column :regional_calendars, :complete, :boolean, default: false, null: false
  end
end
