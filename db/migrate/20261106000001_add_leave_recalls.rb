class AddLeaveRecalls < ActiveRecord::Migration[8.1]
  def up
    add_column :leave_requests, :recalled_on, :date
    remove_check_constraint :leave_requests, name: "leave_requests_valid_status"
    add_check_constraint :leave_requests, "status IN (0, 1, 2, 3, 4)", name: "leave_requests_valid_status"
    add_check_constraint :leave_requests,
      "(status = 4 AND recalled_on IS NOT NULL AND isfinite(recalled_on) " \
        "AND recalled_on > starts_on AND recalled_on <= ends_on) OR " \
        "(status <> 4 AND recalled_on IS NULL)", name: "leave_requests_recall_date"

    execute "ALTER TABLE leave_requests DROP CONSTRAINT leave_requests_no_overlapping_active_periods"
    execute <<~SQL
      ALTER TABLE leave_requests
      ADD CONSTRAINT leave_requests_no_overlapping_active_periods
      EXCLUDE USING gist (
        employee_id WITH =,
        tsrange(
          starts_on + (COALESCE(start_minute, start_part * 720) * interval '1 minute'),
          CASE WHEN recalled_on IS NOT NULL THEN recalled_on::timestamp
            ELSE ends_on + (COALESCE(end_minute, (end_part + 1) * 720) * interval '1 minute') END,
          '[)'
        ) WITH &&
      ) WHERE (status IN (0, 1, 4))
    SQL

    remove_check_constraint :leave_request_events, name: "leave_request_events_valid_type"
    add_check_constraint :leave_request_events, "event_type BETWEEN 0 AND 10",
      name: "leave_request_events_valid_type"
    remove_check_constraint :leave_request_events, name: "leave_request_events_valid_to_status"
    add_check_constraint :leave_request_events, "to_status IN (0, 1, 2, 3, 4)",
      name: "leave_request_events_valid_to_status"

    create_table :leave_recalls do |t|
      t.references :leave_request, null: false, foreign_key: true
      t.references :requested_by, null: false, foreign_key: { to_table: :users }
      t.date :return_on, null: false
      t.text :reason, null: false
      t.boolean :eligibility_confirmed, null: false, default: false
      t.integer :status, null: false, default: 0
      t.datetime :responded_at
      t.integer :remainder_option
      t.text :remainder_preference
      t.references :confirmed_by, foreign_key: { to_table: :users }
      t.datetime :confirmed_at
      t.string :order_number, limit: 100
      t.string :consent_reference, limit: 200
      t.date :order_on
      t.integer :unused_days
      t.timestamps
    end
    add_index :leave_recalls, :leave_request_id, unique: true,
      where: "status IN (0, 1)", name: "leave_recalls_one_open_per_request"
    add_index :leave_recalls, :leave_request_id, unique: true,
      where: "status = 4", name: "leave_recalls_one_confirmation_per_request"
    add_check_constraint :leave_recalls, "status IN (0, 1, 2, 3, 4)", name: "leave_recalls_valid_status"
    add_check_constraint :leave_recalls, "eligibility_confirmed", name: "leave_recalls_eligibility_confirmed"
    add_check_constraint :leave_recalls,
      "isfinite(return_on) AND return_on BETWEEN DATE '2000-01-01' AND DATE '2100-12-31'",
      name: "leave_recalls_supported_return_date"
    add_check_constraint :leave_recalls,
      "remainder_option IS NULL OR remainder_option IN (0, 1)", name: "leave_recalls_valid_remainder_option"
    add_check_constraint :leave_recalls,
      "status NOT IN (1, 4) OR (responded_at IS NOT NULL AND remainder_option IS NOT NULL)",
      name: "leave_recalls_consent_required"
    add_check_constraint :leave_recalls,
      "status <> 2 OR responded_at IS NOT NULL", name: "leave_recalls_decline_recorded"
    add_check_constraint :leave_recalls,
      "(status = 4 AND confirmed_by_id IS NOT NULL AND confirmed_at IS NOT NULL " \
        "AND order_number IS NOT NULL AND length(btrim(order_number)) > 0 " \
        "AND consent_reference IS NOT NULL AND length(btrim(consent_reference)) > 0 " \
        "AND order_on IS NOT NULL AND isfinite(order_on) AND order_on < return_on " \
        "AND unused_days > 0 AND unused_days IS NOT NULL) OR " \
        "(status <> 4 AND confirmed_by_id IS NULL AND confirmed_at IS NULL " \
        "AND order_number IS NULL AND consent_reference IS NULL AND order_on IS NULL AND unused_days IS NULL)",
      name: "leave_recalls_confirmation_complete"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Recall decisions and original leave history must be retained"
  end
end
