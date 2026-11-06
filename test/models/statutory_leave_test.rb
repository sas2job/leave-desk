require "test_helper"

class StatutoryLeaveTest < ActiveSupport::TestCase
  include StatutoryLeaveTestHelper
  setup { prepare_statutory_scenario }

  test "annual leave crosses years excludes holidays and requires legal review" do
    request = LeaveRequest.create!(employee: @employee, leave_type: @annual,
      starts_on: Date.new(2026, 12, 20), ends_on: Date.new(2027, 1, 20))
    assert_equal 24, request.duration_in_days
    assert_equal [ 0, 1440 ], request.attributes.values_at("start_minute", "end_minute")
    assert_raises(ActiveRecord::RecordInvalid) { request.approve!(by: @manager) }
    request.reload
    request.approve!(by: @manager, legal_review: annual_review_attributes)
    assert_predicate request.reload, :approved?
    assert_equal Date.new(2026, 2, 1), request.legal_review.working_year_starts_on
  end

  test "annual leave supports short parts and more than 28 days without invented hard limits" do
    short = LeaveRequest.create!(employee: @employee, leave_type: @annual,
      starts_on: Date.new(2026, 10, 15), ends_on: Date.new(2026, 10, 17))
    short.approve!(by: @manager, legal_review: annual_review_attributes)
    long = LeaveRequest.create!(employee: @employee, leave_type: @annual,
      starts_on: Date.new(2026, 11, 1), ends_on: Date.new(2026, 12, 15))
    assert_operator long.duration_in_days, :>, 28
    long.approve!(by: @manager, legal_review: annual_review_attributes)
    assert_predicate long.reload, :approved?
  end

  test "statutory leaves reject partial days and immutable system holiday policies" do
    [ @annual, @maternity, @childcare, @birthday ].each do |type|
      request = LeaveRequest.new(employee: @employee, leave_type: type,
        starts_on: Date.new(2026, 10, 20), ends_on: Date.new(2026, 10, 20), start_time: "09:00", end_time: "18:00")
      assert_not request.valid?
    end
    assert_not @annual.update(holiday_handling: :include_public_holidays)
    assert_not @maternity.update(holiday_handling: :exclude_public_holidays)
    assert_not @maternity.reload.update(code: "OTHER")
  end

  test "minor annual entitlement is at least 31 while the requested part may be shorter" do
    @employee.update!(birthday_on: Date.new(2009, 1, 1))
    request = LeaveRequest.create!(employee: @employee, leave_type: @annual,
      starts_on: Date.new(2026, 10, 20), ends_on: Date.new(2026, 10, 21))
    assert_raises(ActiveRecord::RecordInvalid) { request.approve!(by: @manager, legal_review: annual_review_attributes) }
    request.reload
    request.approve!(by: @manager, legal_review: annual_review_attributes.merge(entitlement_days: 31))
    assert_predicate request.reload, :approved?
  end

  test "maternity registration accepts documented late start instead of fixed length templates" do
    request = LeaveRequest.create!(employee: @employee, leave_type: @maternity,
      starts_on: Date.new(2026, 10, 1), ends_on: Date.new(2027, 2, 1))
    assert_not request.calendar_unverified?
    assert_raises(LeaveRequest::InvalidTransition) { request.approve!(by: @manager) }
    assert_raises(LeaveRequest::InvalidTransition) { request.reject!(by: @manager) }
    assert_no_difference([ "LeaveRequestEvent.count", "Notification.count" ]) do
      assert_raises(ActiveRecord::RecordInvalid) do
        request.register_family!(by: @administrator, legal_review: family_review_attributes.merge(
          document_starts_on: Date.new(2026, 10, 2), document_ends_on: request.ends_on))
      end
    end
    request.reload
    request.register_family!(by: @administrator, legal_review: family_review_attributes.merge(
      document_starts_on: Date.new(2026, 9, 20), document_ends_on: request.ends_on))
    assert_predicate request.reload, :approved?
    assert_equal @administrator, request.reviewer
    assert_equal "statutory_registered", request.events.order(:id).last.event_type
  end

  test "childcare includes third birthday and accepts father guardian and foster parent" do
    request = create_childcare
    assert_equal Date.new(2028, 1, 1), request.ends_on
    assert_equal @administrator, Notification.last.recipient
    request.register_family!(by: @administrator, legal_review: family_review_attributes)
    assert_predicate request.reload, :approved?
    invalid = LeaveRequest.new(employee: @employee, leave_type: @childcare,
      child_born_on: Date.new(2025, 1, 1), care_relationship: :guardian,
      starts_on: Date.new(2028, 1, 2), ends_on: Date.new(2028, 1, 3))
    assert_not invalid.valid?
    another = User.create!(name: "Foster Parent", email_address: "foster@example.test", password: "test-password")
    assert LeaveRequest.new(employee: another, leave_type: @childcare, care_relationship: :foster_parent,
      child_born_on: Date.new(2025, 1, 1), starts_on: Date.new(2026, 10, 20), ends_on: Date.new(2027, 1, 1)).valid?
  end

  test "employee ends childcare today without manager permission and resumes with linked history" do
    request = create_childcare
    request.register_family!(by: @administrator, legal_review: family_review_attributes)
    original = request.attributes.slice("starts_on", "ends_on", "duration_minutes", "reviewer_id", "reviewed_at")
    assert_raises(LeaveRequest::InvalidTransition) { request.cancel!(by: @employee) }
    assert_raises(LeaveRequest::ReviewNotAuthorized) { request.return_from_childcare!(by: @manager, return_on: Date.current) }
    request.return_from_childcare!(by: @employee, return_on: Date.current)
    assert_predicate request.reload, :interrupted?
    assert_equal original, request.attributes.slice(*original.keys)
    assert_equal Date.current - 1, request.effective_ends_on
    resumed = create_childcare(starts_on: Date.new(2026, 11, 1), resumes_request: request)
    resumed.register_family!(by: @administrator, legal_review: family_review_attributes)
    assert_equal request, resumed.resumes_request
    used = LeaveRequest.new(employee: @employee, leave_type: @annual, starts_on: Date.new(2026, 10, 15), ends_on: Date.new(2026, 10, 15))
    assert_predicate used, :valid?
  end

  test "leap day boundary needs a separate legal confirmation for both proposed end dates" do
    request = create_childcare(child_born_on: Date.new(2024, 2, 29), ends_on: Date.new(2027, 3, 1))
    assert_raises(ActiveRecord::RecordInvalid) { request.register_family!(by: @administrator, legal_review: family_review_attributes) }
    request.reload
    request.register_family!(by: @administrator, legal_review: family_review_attributes.merge(age_boundary_confirmed: true))
    assert_predicate request.reload, :approved?
  end

  test "birthday is exactly one full day and one claim per employee per calendar year" do
    first = LeaveRequest.create!(employee: @employee, leave_type: @birthday,
      starts_on: Date.new(2026, 10, 20), ends_on: Date.new(2026, 10, 20))
    assert_equal 1, first.duration_in_days
    second = LeaveRequest.new(employee: @employee, leave_type: @birthday,
      starts_on: Date.new(2026, 10, 25), ends_on: Date.new(2026, 10, 25))
    assert_not second.valid?
    attributes = first.attributes.except("id").merge("starts_on" => Date.new(2026, 10, 25), "ends_on" => Date.new(2026, 10, 25))
    error = assert_raises(ActiveRecord::RecordNotUnique) do
      LeaveRequest.transaction(requires_new: true) { LeaveRequest.insert_all!([ attributes ]) }
    end
    assert_kind_of PG::UniqueViolation, error.cause
    first.cancel!
    second.save!
    second.approve!(by: @manager)
    travel_to(Time.zone.local(2026, 10, 26, 12)) { second.cancel! }
    assert_predicate second.reload, :birthday_used?
    third = LeaveRequest.new(employee: @employee, leave_type: @birthday,
      starts_on: Date.new(2026, 11, 1), ends_on: Date.new(2026, 11, 1))
    assert_not third.valid?
  end
end
