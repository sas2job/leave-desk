class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :notifications do |t|
      t.references :recipient, null: false, foreign_key: { to_table: :users }
      t.references :leave_request_event, null: false, foreign_key: true, index: { unique: true }
      t.datetime :read_at
      t.timestamps
    end
  end
end
