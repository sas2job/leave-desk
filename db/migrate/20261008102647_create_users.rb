class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email_address, null: false
      t.string :name, null: false
      t.integer :role, null: false, default: 0
      t.references :manager, foreign_key: { to_table: :users }
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :users, "LOWER(email_address)", unique: true,
      name: "index_users_on_lower_email_address"
  end
end
