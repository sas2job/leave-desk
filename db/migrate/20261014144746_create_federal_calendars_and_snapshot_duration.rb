class CreateFederalCalendarsAndSnapshotDuration < ActiveRecord::Migration[8.1]
  FIXED_HOLIDAYS = [
    [ 1, 1 ], [ 1, 2 ], [ 1, 3 ], [ 1, 4 ], [ 1, 5 ], [ 1, 6 ], [ 1, 7 ], [ 1, 8 ],
    [ 2, 23 ], [ 3, 8 ], [ 5, 1 ], [ 5, 9 ], [ 6, 12 ], [ 11, 4 ]
  ].freeze

  def change
    create_table :federal_calendars do |t|
      t.integer :year, null: false
      t.text :legal_basis, null: false
      t.date :public_holidays, array: true, default: [], null: false
      t.jsonb :transfers, default: [], null: false
      t.timestamps
    end
    add_index :federal_calendars, :year, unique: true
    add_check_constraint :federal_calendars, "year BETWEEN 2000 AND 2100", name: "federal_calendars_supported_year"
    add_check_constraint :federal_calendars, "jsonb_typeof(transfers) = 'array'", name: "federal_calendars_transfers_array"

    add_column :leave_requests, :duration_half_days, :integer
    reversible do |direction|
      direction.up { backfill_duration }
    end
    change_column_null :leave_requests, :duration_half_days, false
    add_check_constraint :leave_requests, "duration_half_days > 0", name: "leave_requests_positive_duration"
  end

  private

  def backfill_duration
    suppress_messages do
      backfill_rows
    end
  end

  def backfill_rows
    rows = select_all(<<~SQL)
      SELECT requests.id, requests.starts_on, requests.ends_on, requests.start_part,
             requests.end_part, types.holiday_handling
      FROM leave_requests requests
      INNER JOIN leave_types types ON types.id = requests.leave_type_id
    SQL
    rows.each do |row|
      first_date = Date.iso8601(row.fetch("starts_on").to_s)
      last_date = Date.iso8601(row.fetch("ends_on").to_s)
      excluded = if row.fetch("holiday_handling").to_i == 1
        (first_date.year..last_date.year).sum do |year|
          FIXED_HOLIDAYS.count { |month, day| (first_date..last_date).cover?(Date.new(year, month, day)) }
        end
      else
        0
      end
      first_counted = row.fetch("holiday_handling").to_i == 0 || !FIXED_HOLIDAYS.include?([ first_date.month, first_date.day ])
      last_counted = row.fetch("holiday_handling").to_i == 0 || !FIXED_HOLIDAYS.include?([ last_date.month, last_date.day ])
      half_days = (last_date.jd - first_date.jd + 1 - excluded) * 2
      half_days -= 1 if row.fetch("start_part").to_i == 1 && first_counted
      half_days -= 1 if row.fetch("end_part").to_i == 0 && last_counted
      execute "UPDATE leave_requests SET duration_half_days = #{half_days} WHERE id = #{Integer(row.fetch('id'))}"
    end
  end
end
