class RestoreCancelledRequestApprovalEvents < ActiveRecord::Migration[8.1]
  def up
    inconsistent_count = select_value(<<~SQL).to_i
      SELECT COUNT(*)
      FROM leave_requests requests
      JOIN leave_request_events cancellations
        ON cancellations.leave_request_id = requests.id
       AND cancellations.event_type = 3
       AND cancellations.from_status = 0
      WHERE requests.status = 3
        AND requests.reviewer_id IS NOT NULL
        AND requests.reviewed_at IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM leave_request_events reviews
          WHERE reviews.leave_request_id = requests.id AND reviews.event_type IN (1, 2)
        )
        AND (requests.reviewed_at < requests.created_at OR
             requests.reviewed_at > cancellations.occurred_at)
    SQL
    if inconsistent_count.positive?
      raise ActiveRecord::MigrationError,
        "Cannot reconstruct approval order for #{inconsistent_count} cancelled requests"
    end

    execute <<~SQL
      WITH repaired AS (
        INSERT INTO leave_request_events
          (leave_request_id, actor_id, event_type, from_status, to_status, comment, occurred_at)
        SELECT requests.id, requests.reviewer_id, 1, 0, 1,
               requests.review_comment, requests.reviewed_at
        FROM leave_requests requests
        WHERE requests.status = 3
          AND requests.reviewer_id IS NOT NULL
          AND requests.reviewed_at IS NOT NULL
          AND EXISTS (
            SELECT 1 FROM leave_request_events cancellations
            WHERE cancellations.leave_request_id = requests.id
              AND cancellations.event_type = 3
              AND cancellations.from_status = 0
          )
          AND NOT EXISTS (
            SELECT 1 FROM leave_request_events reviews
            WHERE reviews.leave_request_id = requests.id
              AND reviews.event_type IN (1, 2)
          )
        RETURNING leave_request_id
      )
      UPDATE leave_request_events cancellations
      SET from_status = 1
      FROM repaired
      WHERE cancellations.leave_request_id = repaired.leave_request_id
        AND cancellations.event_type = 3
        AND cancellations.from_status = 0
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "Restored historical approvals must not be removed"
  end
end
