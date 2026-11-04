class AddRegionalCalendars < ActiveRecord::Migration[8.1]
  def change
    create_table :regions do |t|
      t.string :code, null: false
      t.string :name, null: false
      t.timestamps
    end
    add_index :regions, :code, unique: true

    create_table :regional_calendars do |t|
      t.references :region, null: false, foreign_key: true
      t.integer :year, null: false
      t.text :legal_basis, null: false
      t.date :public_holidays, array: true, default: [], null: false
      t.date :additional_days_off, array: true, default: [], null: false
      t.timestamps
    end
    add_index :regional_calendars, [ :region_id, :year ], unique: true
    add_check_constraint :regional_calendars, "year BETWEEN 2000 AND 2100",
      name: "regional_calendars_supported_year"

    add_reference :users, :region, foreign_key: true
    add_reference :leave_requests, :region, foreign_key: true
  end
end
