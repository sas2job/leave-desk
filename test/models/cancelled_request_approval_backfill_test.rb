require "test_helper"
require Rails.root.join("db/migrate/20261015103423_restore_cancelled_request_approval_events")

class CancelledRequestApprovalBackfillTest < ActiveSupport::TestCase
  test "restores only missing approval before cancellation with original review details" do
    employee = User.create!(name: "Employee", email_address: "employee@example.test",
      password: "test-password")
    reviewer = User.create!(name: "Reviewer", email_address: "reviewer@example.test",
      password: "test-password", role: :manager)
    leave_type = LeaveType.create!(name: "Annual", code: "TEST_ANNUAL")
    reviewed_at = Time.zone.local(2026, 10, 14, 13)
    cancelled_at = reviewed_at + 1.hour

    pending = request_for(employee, leave_type, 1)
    approved = request_for(employee, leave_type, 3)
    set_review(approved, :approved, reviewer, reviewed_at)
    add_review_event(approved, :approved, reviewer, reviewed_at)
    rejected = request_for(employee, leave_type, 5)
    set_review(rejected, :rejected, reviewer, reviewed_at)
    add_review_event(rejected, :rejected, reviewer, reviewed_at)
    directly_cancelled = request_for(employee, leave_type, 7)
    set_cancellation(directly_cancelled, cancelled_at)
    approved_then_cancelled = request_for(employee, leave_type, 9)
    set_cancellation(approved_then_cancelled, cancelled_at,
      reviewer:, reviewed_at:, review_comment: "Approved earlier")

    migration = RestoreCancelledRequestApprovalEvents.new
    migration.up
    migration.up

    assert_equal %w[created], event_types(pending)
    assert_equal %w[created approved], event_types(approved)
    assert_equal %w[created rejected], event_types(rejected)
    assert_equal %w[created cancelled], event_types(directly_cancelled)
    assert_equal 0, directly_cancelled.events.cancelled.sole.from_status

    assert_equal %w[created approved cancelled], event_types(approved_then_cancelled)
    approval = approved_then_cancelled.events.approved.sole
    assert_equal reviewer.id, approval.actor_id
    assert_equal reviewed_at, approval.occurred_at
    assert_equal "Approved earlier", approval.comment
    assert_equal 0, approval.from_status
    assert_equal 1, approval.to_status
    assert_equal 1, approved_then_cancelled.events.cancelled.sole.from_status
    assert_equal cancelled_at, approved_then_cancelled.events.cancelled.sole.occurred_at
  end

  test "stops without changing history when review follows cancellation" do
    employee = User.create!(name: "Employee", email_address: "employee@example.test",
      password: "test-password")
    reviewer = User.create!(name: "Reviewer", email_address: "reviewer@example.test",
      password: "test-password", role: :manager)
    leave_type = LeaveType.create!(name: "Annual", code: "TEST_ANNUAL")
    request = request_for(employee, leave_type, 1)
    cancelled_at = Time.zone.local(2026, 10, 14, 13)
    set_cancellation(request, cancelled_at, reviewer:,
      reviewed_at: cancelled_at + 1.hour, review_comment: "Inconsistent")

    assert_raises(ActiveRecord::MigrationError) do
      RestoreCancelledRequestApprovalEvents.new.up
    end
    assert_equal %w[created cancelled], event_types(request)
    assert_equal 0, request.events.cancelled.sole.from_status
  end

  private

  def request_for(employee, leave_type, day)
    date = Date.new(2026, 12, day)
    LeaveRequest.create!(employee:, leave_type:, starts_on: date, ends_on: date)
  end

  def set_review(request, status, reviewer, reviewed_at)
    request.update_columns(status: LeaveRequest.statuses.fetch(status.to_s),
      reviewer_id: reviewer.id, reviewed_at:, review_comment: "Reviewed")
  end

  def set_cancellation(request, cancelled_at, reviewer: nil, reviewed_at: nil,
    review_comment: nil)
    request.update_columns(status: LeaveRequest.statuses.fetch("cancelled"),
      reviewer_id: reviewer&.id, reviewed_at:, review_comment:, updated_at: cancelled_at)
    LeaveRequestEvent.insert_all!([ { leave_request_id: request.id, actor_id: request.employee_id,
      event_type: LeaveRequestEvent.event_types.fetch("cancelled"), from_status: 0,
      to_status: LeaveRequest.statuses.fetch("cancelled"), occurred_at: cancelled_at } ])
  end

  def add_review_event(request, status, reviewer, reviewed_at)
    LeaveRequestEvent.insert_all!([ { leave_request_id: request.id, actor_id: reviewer.id,
      event_type: LeaveRequestEvent.event_types.fetch(status.to_s), from_status: 0,
      to_status: LeaveRequest.statuses.fetch(status.to_s), comment: "Reviewed",
      occurred_at: reviewed_at } ])
  end

  def event_types(request)
    request.events.where(event_type: 0..3).order(:occurred_at, :id).pluck(:event_type)
  end
end
