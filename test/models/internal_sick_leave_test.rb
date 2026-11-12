require "test_helper"

class InternalSickLeaveTest < ActiveSupport::TestCase
  setup do
    @manager = User.create!(name: "Sick Manager", email_address: "sick-manager@example.test", password: "test-password", role: :manager)
    @employee = User.create!(name: "Sick Employee", email_address: "sick-employee@example.test", password: "test-password", manager: @manager)
    @type = LeaveType.find_or_create_by!(code: "SICK") { |type| type.name = "Sick" }
  end

  test "full day sick submission supports past dates and year boundary without configured calendars" do
    request = build_request(starts_on: Date.new(2025, 12, 30), ends_on: Date.new(2026, 1, 2))
    assert request.submit, request.errors.full_messages.to_sentence
    assert_equal 5, request.legal_kind
    assert_equal 4, request.duration_in_days
    assert_not request.calendar_unverified?
    assert_predicate request, :pending?
  end

  test "partial days are rejected by model and database" do
    request = build_request(start_time: "09:00", end_time: "12:00")
    assert_not request.valid?
    assert_match(/полными календарными днями/, request.errors.full_messages.join)
    request = build_request.tap(&:save!)
    assert_raises(ActiveRecord::StatementInvalid) do
      LeaveRequest.transaction(requires_new: true) { request.update_columns(end_minute: 720) }
    end
  end

  test "long period is warning rather than a hard limit" do
    request = build_request(ends_on: Date.new(2027, 2, 1))
    assert request.valid?, request.errors.full_messages.to_sentence
    assert_predicate request, :long_sick_period?
    assert_not build_request(ends_on: Date.new(2026, 10, 30)).long_sick_period?
  end

  test "calendar changes do not flag full day sickness for recalculation" do
    request = approved_request
    assert_no_difference "LeaveRequestEvent.count" do
      request.flag_calendar_for_review!
    end
    assert_not request.reload.calendar_unverified?
    assert_equal 10, request.duration_in_days
  end

  test "proposal does not extend calendar until manager approves and preserves initial review" do
    request = approved_request
    original_review = request.attributes.slice("reviewer_id", "reviewed_at")
    extension = propose(request, Date.new(2026, 10, 20))
    assert_equal Date.new(2026, 10, 10), request.reload.ends_on
    assert_equal 10, request.duration_in_days
    assert_equal "sick_extension_proposed", @manager.notifications.last.leave_request_event.event_type
    extension.review!(by: @manager, approve: true)
    assert_equal Date.new(2026, 10, 20), request.reload.ends_on
    assert_equal 20, request.duration_in_days
    assert_equal original_review, request.attributes.slice("reviewer_id", "reviewed_at")
    assert_equal @manager, extension.reviewer
    assert_predicate extension, :approved?
    assert_equal "sick_extension_approved", @employee.notifications.last.leave_request_event.event_type
    assert_raises(LeaveRequest::InvalidTransition) { extension.review!(by: @manager, approve: true) }
    assert_equal Date.new(2026, 10, 10), extension.previous_ends_on
    assert_not extension.destroy
  end

  test "rejection keeps confirmed dates and permits a new proposal" do
    request = approved_request
    extension = propose(request, Date.new(2026, 10, 20))
    extension.review!(by: @manager, approve: false)
    assert_equal Date.new(2026, 10, 10), request.reload.ends_on
    assert_predicate extension, :rejected?
    assert propose(request, Date.new(2026, 10, 18)).persisted?
  end

  test "duplicate extension and invalid dates cannot be submitted" do
    request = approved_request
    assert_raises(ActiveRecord::RecordInvalid) { propose(request, request.ends_on) }
    assert_raises(ActiveRecord::RecordInvalid) { propose(request, nil) }
    propose(request, Date.new(2026, 10, 20))
    assert_raises(LeaveRequest::InvalidTransition) { propose(request, Date.new(2026, 10, 21)) }
  end

  test "overlap at approval rolls back request extension history and notifications" do
    request = approved_request
    extension = propose(request, Date.new(2026, 10, 20))
    build_request(starts_on: Date.new(2026, 10, 15), ends_on: Date.new(2026, 10, 16)).save!
    assert_no_difference [ "LeaveRequestEvent.count", "Notification.count" ] do
      assert_raises(ActiveRecord::RecordInvalid) { extension.review!(by: @manager, approve: true) }
    end
    assert_predicate extension.reload, :pending?
    assert_equal Date.new(2026, 10, 10), request.reload.ends_on
    assert_equal 10, request.duration_in_days
  end

  test "only current manager may review and employee cannot self approve" do
    request = approved_request
    extension = propose(request, Date.new(2026, 10, 20))
    assert_raises(LeaveRequest::ReviewNotAuthorized) { extension.review!(by: @employee, approve: true) }
    replacement = User.create!(name: "Replacement", email_address: "sick-replacement@example.test", password: "test-password", role: :manager)
    @employee.update!(manager: replacement)
    assert_raises(LeaveRequest::ReviewNotAuthorized) { extension.review!(by: @manager, approve: true) }
    extension.review!(by: replacement, approve: true)
    assert_predicate extension.reload, :approved?
  end

  test "only employee can extend or close and inactive actor cannot act" do
    request = approved_request
    assert_raises(LeaveRequest::ReviewNotAuthorized) do
      SickLeaveExtension.propose!(leave_request: request, by: @manager, proposed_ends_on: Date.new(2026, 10, 20))
    end
    assert_raises(LeaveRequest::ReviewNotAuthorized) { request.close_sick_leave!(by: @manager, closed_on: request.ends_on) }
    @employee.update!(active: false)
    assert_raises(LeaveRequest::ReviewNotAuthorized) { propose(request, Date.new(2026, 10, 20)) }
  end

  test "closing records actual end and withdraws pending extension atomically" do
    request = approved_request
    extension = propose(request, Date.new(2026, 10, 20))
    assert_predicate request, :sick_needs_clarification?
    request.close_sick_leave!(by: @employee, closed_on: Date.new(2026, 10, 8))
    assert_equal Date.new(2026, 10, 8), request.reload.ends_on
    assert_equal request.ends_on, request.sick_closed_on
    assert_equal 8, request.duration_in_days
    assert_predicate request, :approved?
    assert_not request.sick_needs_clarification?
    assert_predicate extension.reload, :withdrawn?
    assert_match(/10\.10\.2026/, request.events.sick_closed.last.comment)
    assert_raises(LeaveRequest::InvalidTransition) { request.close_sick_leave!(by: @employee, closed_on: request.ends_on) }
    assert_raises(LeaveRequest::InvalidTransition) { propose(request, Date.new(2026, 10, 20)) }
    assert_raises(LeaveRequest::InvalidTransition) { request.cancel!(by: @employee) }
  end

  test "closing cannot exceed confirmed period today or precede start" do
    request = approved_request
    [ nil, Date.new(2026, 9, 30), Date.new(2026, 10, 11) ].each do |date|
      assert_raises(LeaveRequest::InvalidTransition) { request.close_sick_leave!(by: @employee, closed_on: date) }
    end
    travel_to Time.zone.local(2026, 10, 5, 12) do
      assert_raises(LeaveRequest::InvalidTransition) { request.close_sick_leave!(by: @employee, closed_on: Date.new(2026, 10, 6)) }
    end
  end

  test "cancellation withdraws pending extensions and prevents decisions" do
    request = approved_request
    extension = propose(request, Date.new(2026, 10, 20))
    request.cancel!(by: @employee)
    assert_predicate extension.reload, :withdrawn?
    assert_raises(LeaveRequest::InvalidTransition) { extension.review!(by: @manager, approve: true) }
  end

  test "pending non sick and closed requests cannot be extended" do
    request = build_request.tap(&:save!)
    assert_raises(LeaveRequest::InvalidTransition) { propose(request, Date.new(2026, 10, 20)) }
    @type = LeaveType.create!(name: "Other", code: "OTHER")
    other = build_request(starts_on: Date.new(2026, 11, 1), ends_on: Date.new(2026, 11, 5)).tap(&:save!)
    other.approve!(by: @manager)
    assert_raises(LeaveRequest::InvalidTransition) { propose(other, Date.new(2026, 11, 20)) }
  end

  test "direct period and closure mutation is rejected" do
    request = approved_request
    assert_not request.update(ends_on: Date.new(2026, 10, 20))
    request.reload
    assert_not request.update(sick_closed_on: request.ends_on, sick_closed_at: Time.current)
  end

  test "database permits only one pending extension and requires a distinct reviewer for a decision" do
    request = approved_request
    extension = propose(request, Date.new(2026, 10, 20))
    assert_raises(ActiveRecord::RecordNotUnique) do
      SickLeaveExtension.transaction(requires_new: true) do
        SickLeaveExtension.create!(leave_request: request, requested_by: @employee,
          previous_ends_on: request.ends_on, proposed_ends_on: Date.new(2026, 10, 21))
      end
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      SickLeaveExtension.transaction(requires_new: true) do
        extension.update_columns(status: SickLeaveExtension.statuses.fetch(:approved), reviewer_id: @employee.id, reviewed_at: Time.current)
      end
    end
    assert_predicate extension.reload, :pending?
  end

  test "legacy full day sick leave keeps its duration when extended and partial history is retained" do
    request = approved_request
    LeaveRequest.where(id: request.id).update_all(legal_kind: 0, start_minute: nil, end_minute: nil, duration_minutes: nil, duration_half_days: 20)
    request.reload
    extension = propose(request, Date.new(2026, 10, 20))
    extension.review!(by: @manager, approve: true)
    assert_equal 20, request.reload.duration_in_days
    assert_equal 0, request.start_minute
    assert_equal 1440, request.end_minute
    request.update_columns(end_minute: 720, duration_minutes: 19 * 1440 + 720)
    original = request.reload.attributes
    assert_raises(LeaveRequest::InvalidTransition) { propose(request, Date.new(2026, 10, 21)) }
    assert_equal original, request.reload.attributes
  end

  private

  def build_request(**attributes)
    LeaveRequest.new({ employee: @employee, leave_type: @type, starts_on: Date.new(2026, 10, 1), ends_on: Date.new(2026, 10, 10) }.merge(attributes))
  end

  def approved_request
    build_request.tap do |request|
      request.save!
      request.approve!(by: @manager)
    end
  end

  def propose(request, date)
    SickLeaveExtension.propose!(leave_request: request, by: @employee, proposed_ends_on: date)
  end
end
