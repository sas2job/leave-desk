class IndexHistoryPages < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :leave_requests, [ :employee_id, :id ], algorithm: :concurrently
    add_index :notifications, [ :recipient_id, :id ], algorithm: :concurrently
  end
end
