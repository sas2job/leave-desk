class AddEmployeeCityAndTimeZone < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :city, :string
    add_column :users, :time_zone, :string, default: "Europe/Moscow", null: false
  end
end
