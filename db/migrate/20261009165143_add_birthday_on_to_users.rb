class AddBirthdayOnToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :birthday_on, :date
  end
end
