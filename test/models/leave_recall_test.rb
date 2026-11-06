require "test_helper"

class LeaveRecallTest < ActiveSupport::TestCase
  include LeaveRecallTestHelper

  setup { prepare_recall_scenario }

  test "proposal consent and confirmation preserve original decision and shorten only effective period" do
    original = @leave_request.attributes.slice("starts_on", "ends_on", "duration_minutes", "reviewer_id", "reviewed_at")
    recall = propose_recall
    assert_predicate @leave_request.reload, :approved?
    assert_equal @employee, Notification.last.recipient
    consent_to_recall(recall)
    assert_predicate @leave_request.reload, :approved?
    assert_equal @manager, Notification.last.recipient

    assert_difference([ "LeaveRequestEvent.count", "Notification.count" ], 1) { confirm_recall(recall) }
    assert_predicate @leave_request.reload, :recalled?
    assert_equal original, @leave_request.attributes.slice(*original.keys)
    assert_equal Date.new(2026, 10, 15), @leave_request.effective_ends_on
    assert_equal 5, recall.reload.unused_days
    assert_equal @employee, Notification.last.recipient
    assert_equal %w[created approved recall_proposed recall_consented recalled], @leave_request.events.order(:id).pluck(:event_type)
    assert_equal [ 1, 4 ], @leave_request.events.recalled.last.attributes.values_at("from_status", "to_status")
  end

  test "decline and silence leave approval and dates intact" do
    recall = propose_recall
    assert_predicate @leave_request.reload, :approved?
    assert_nil @leave_request.recalled_on
    recall.decline!(by: @employee)
    assert_predicate recall.reload, :declined?
    assert_predicate @leave_request.reload, :approved?
    assert_equal Date.new(2026, 10, 20), @leave_request.effective_ends_on
    assert_equal @manager, Notification.last.recipient
    assert_no_difference([ "LeaveRequestEvent.count", "Notification.count" ]) do
      assert_raises(LeaveRecall::InvalidTransition) { confirm_recall(recall) }
    end
  end

  test "consent alone cannot be treated as an order and can be withdrawn" do
    recall = propose_recall
    assert_raises(LeaveRecall::InvalidTransition) { confirm_recall(recall) }
    consent_to_recall(recall)
    recall.withdraw!(by: @employee)
    assert_predicate @leave_request.reload, :approved?
    assert_predicate recall.reload, :withdrawn?
    assert_raises(LeaveRecall::InvalidTransition) { confirm_recall(recall) }
  end

  test "only employee may respond and only current manager may confirm" do
    recall = propose_recall
    assert_raises(LeaveRecall::NotAuthorized) { recall.decline!(by: @manager) }
    consent_to_recall(recall)
    other_manager = User.create!(name: "Other Manager", email_address: "recall-other@example.test",
      password: "test-password", role: :manager)
    @employee.update!(manager: other_manager)
    assert_no_difference([ "LeaveRequestEvent.count", "Notification.count" ]) do
      assert_raises(LeaveRecall::NotAuthorized) { confirm_recall(recall) }
    end
    assert_predicate @leave_request.reload, :approved?
  end

  test "minor and missing eligibility confirmation cannot be recalled" do
    assert_raises(ActiveRecord::RecordInvalid) { propose_recall(eligibility_confirmed: false) }
    @employee.update!(birthday_on: Date.new(2009, 1, 1))
    assert_no_difference([ "LeaveRecall.count", "LeaveRequestEvent.count", "Notification.count" ]) do
      assert_raises(LeaveRecall::InvalidTransition) { propose_recall }
    end
  end

  test "pending cancelled unverified and partial day requests cannot be recalled" do
    %i[pending cancelled].each do |status|
      @leave_request.update!(status:)
      assert_raises(LeaveRecall::InvalidTransition) { propose_recall }
    end
    @leave_request.update!(status: :approved, calendar_unverified: true)
    assert_raises(LeaveRecall::InvalidTransition) { propose_recall }
    LeaveRequest.where(id: @leave_request.id).update_all(calendar_unverified: false, start_minute: 540, legal_kind: 0)
    @leave_request.reload
    assert_raises(LeaveRecall::InvalidTransition) { propose_recall }
  end

  test "dates must be future within already started annual leave" do
    [ nil, Date.new(2026, 10, 14), Date.new(2026, 10, 21) ].each do |return_on|
      assert_raises(LeaveRecall::InvalidTransition) { propose_recall(return_on:) }
    end
    travel_to Time.zone.local(2026, 9, 30, 12) do
      assert_raises(LeaveRecall::InvalidTransition) { propose_recall }
    end
    @annual.update_column(:code, "UNPAID_RECALL_TEST")
    assert_raises(LeaveRecall::InvalidTransition) { propose_recall }
  end

  test "employee must choose remaining leave and document and order are required" do
    recall = propose_recall
    assert_raises(ActiveRecord::RecordInvalid) do
      recall.consent!(by: @employee, remainder_option: :choose_dates, remainder_preference: "")
    end
    recall.reload
    recall.consent!(by: @employee, remainder_option: :next_work_year)
    assert_no_difference([ "LeaveRequestEvent.count", "Notification.count" ]) do
      assert_raises(ActiveRecord::RecordInvalid) { confirm_recall(recall, consent_reference: "") }
    end
    recall.reload
    assert_raises(ActiveRecord::RecordInvalid) { confirm_recall(recall, order_on: Date.new(2026, 10, 13)) }
    assert_predicate @leave_request.reload, :approved?
  end

  test "a past return date or cancelled request cannot be confirmed after consent" do
    recall = propose_recall
    consent_to_recall(recall)
    travel_to Time.zone.local(2026, 10, 16, 12) do
      assert_raises(LeaveRecall::InvalidTransition) { confirm_recall(recall) }
    end
    @leave_request.cancel!(by: @employee)
    assert_raises(LeaveRecall::InvalidTransition) { confirm_recall(recall) }
  end

  test "database rejects duplicate open recalls and confirmation without consent" do
    recall = propose_recall
    attributes = recall.attributes.except("id")
    assert_raises(ActiveRecord::RecordNotUnique) do
      LeaveRecall.transaction(requires_new: true) { LeaveRecall.insert_all!([ attributes ]) }
    end
    error = assert_raises(ActiveRecord::StatementInvalid) do
      LeaveRecall.transaction(requires_new: true) { recall.update_columns(status: 4) }
    end
    assert_kind_of PG::CheckViolation, error.cause
    assert_predicate recall.reload, :proposed?
  end

  test "recalled tail is free for a new request while used dates remain protected by database" do
    recall = propose_recall
    consent_to_recall(recall)
    confirm_recall(recall)
    replacement = LeaveRequest.create!(employee: @employee, leave_type: @annual,
      starts_on: Date.new(2026, 10, 16), ends_on: Date.new(2026, 10, 17))
    assert_predicate replacement, :persisted?
    conflicting = replacement.attributes.except("id").merge("starts_on" => Date.new(2026, 10, 15), "ends_on" => Date.new(2026, 10, 15))
    error = assert_raises(ActiveRecord::StatementInvalid) do
      LeaveRequest.transaction(requires_new: true) { LeaveRequest.insert_all!([ conflicting ]) }
    end
    assert_kind_of PG::ExclusionViolation, error.cause
    assert_no_difference([ "LeaveRequestEvent.count", "Notification.count" ]) do
      assert_raises(LeaveRecall::InvalidTransition) { confirm_recall(recall) }
    end
  end

  test "unused duration excludes public holidays and stays fixed after confirmation" do
    travel_to Time.zone.local(2026, 11, 1, 12) do
      @leave_request = LeaveRequest.create!(employee: @employee, leave_type: @annual,
        starts_on: Date.new(2026, 11, 1), ends_on: Date.new(2026, 11, 6), start_time: "00:00", end_time: "24:00")
      @leave_request.approve!(by: @manager, legal_review: {
        conditions_confirmed: true, working_year_starts_on: Date.new(2026, 1, 1),
        working_year_ends_on: Date.new(2026, 12, 31), entitlement_days: 28
      })
      recall = propose_recall(return_on: Date.new(2026, 11, 3))
      consent_to_recall(recall)
      confirm_recall(recall, order_on: Date.new(2026, 11, 1))
      assert_equal 3, recall.reload.unused_days
      calendar = FederalCalendar.find_by!(year: 2026)
      calendar.update!(public_holidays: calendar.public_holidays + [ Date.new(2026, 11, 5) ])
      assert_equal 3, recall.reload.unused_days
    end
  end
end
