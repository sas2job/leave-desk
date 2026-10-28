WITH histories AS (
  SELECT requests.id,
    requests.reviewer_id,
    requests.reviewed_at,
    requests.review_comment,
    (SELECT COUNT(*) FROM leave_request_events events
      WHERE events.leave_request_id = requests.id
        AND events.event_type = 0
        AND events.occurred_at <= requests.reviewed_at) AS creation_count,
    (SELECT COUNT(*) FROM leave_request_events events
      WHERE events.leave_request_id = requests.id
        AND events.event_type IN (1, 2)) AS review_count,
    (SELECT COUNT(*) FROM leave_request_events events
      WHERE events.leave_request_id = requests.id
        AND events.event_type = 1
        AND events.from_status = 0 AND events.to_status = 1
        AND events.actor_id = requests.reviewer_id
        AND events.comment IS NOT DISTINCT FROM requests.review_comment
        AND events.occurred_at >= requests.reviewed_at) AS approval_count,
    (SELECT COUNT(*) FROM leave_request_events events
      WHERE events.leave_request_id = requests.id
        AND events.event_type = 3) AS cancellation_count,
    (SELECT COUNT(*) FROM leave_request_events events
      WHERE events.leave_request_id = requests.id
        AND events.event_type = 3
        AND events.from_status = 1 AND events.to_status = 3
        AND events.occurred_at >= requests.reviewed_at) AS approved_cancellation_count,
    (SELECT COUNT(*) FROM leave_request_events approvals
      JOIN leave_request_events cancellations
        ON cancellations.leave_request_id = approvals.leave_request_id
      WHERE approvals.leave_request_id = requests.id
        AND approvals.event_type = 1 AND cancellations.event_type = 3
        AND approvals.occurred_at <= cancellations.occurred_at) AS ordered_pair_count,
    (SELECT COUNT(*) FROM leave_request_events events
      WHERE events.leave_request_id = requests.id
        AND events.event_type = 1
        AND events.occurred_at = requests.reviewed_at) AS approval_at_review_time
  FROM leave_requests requests
  WHERE requests.status = 3
    AND requests.reviewer_id IS NOT NULL
    AND requests.reviewed_at IS NOT NULL
), classified AS (
  SELECT *,
    creation_count = 1 AND review_count = 1 AND approval_count = 1
      AND cancellation_count = 1 AND approved_cancellation_count = 1
      AND ordered_pair_count = 1 AS valid
  FROM histories
)
SELECT COUNT(*) AS reviewed_cancelled,
  COUNT(*) FILTER (WHERE valid) AS valid_history,
  COUNT(*) FILTER (WHERE NOT valid) AS invalid_history,
  COALESCE(SUM(approval_at_review_time), 0) AS approvals_at_review_time
FROM classified;
