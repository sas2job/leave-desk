class AddHolidayHandlingToLeaveTypes < ActiveRecord::Migration[8.1]
  def change
    add_column :leave_types, :holiday_handling, :integer, null: false, default: 0
    add_check_constraint :leave_types, "holiday_handling IN (0, 1)",
      name: "leave_types_valid_holiday_handling"

    reversible do |direction|
      direction.up do
        execute <<~SQL
          UPDATE leave_types
          SET holiday_handling = 1
          WHERE code = 'ANNUAL'
        SQL
      end
    end
  end
end
