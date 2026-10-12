require "test_helper"

class LeaveRequestTest < ActiveSupport::TestCase
  setup do
    @manager = User.create!(name: "Review Manager", email_address: "manager@example.test",
      password: "test-password", role: :manager)
    @employee = User.create!(name: "Example Employee", email_address: "employee@example.test",
      password: "test-password", manager: @manager)
    @leave_type = LeaveType.create!(name: "Annual leave", code: "test_annual")
  end

  test "new requests are pending" do
    request = create_request

    assert_predicate request, :pending?
    assert_predicate request.events.first, :created?
  end

  test "end date cannot precede start date" do
    request = LeaveRequest.new(employee: @employee, leave_type: @leave_type,
      starts_on: Date.new(2026, 10, 10), ends_on: Date.new(2026, 10, 9))

    assert_not request.valid?
    assert_includes request.errors[:base], "Дата окончания не может быть раньше даты начала"
  end

  test "rejects unknown half-day values and malformed leave type id" do
    request = LeaveRequest.new(employee: @employee, leave_type_id: "#{@leave_type.id}junk",
      starts_on: Date.new(2026, 10, 10), ends_on: Date.new(2026, 10, 11),
      start_part: "unknown", end_part: "")

    assert_not request.valid?
    assert_includes request.errors[:leave_type], "должен быть выбран из списка"
    assert_predicate request.errors[:start_part], :present?
    assert_predicate request.errors[:end_part], :present?
  end

  test "non-finite dates are rejected without raising" do
    request = LeaveRequest.new(employee: @employee, leave_type: @leave_type,
      starts_on: "infinity", ends_on: "infinity")

    assert_not request.valid?
    assert_includes request.errors[:starts_on], "должна быть между 01.01.2000 и 31.12.2100"
    assert_includes request.errors[:ends_on], "должна быть между 01.01.2000 и 31.12.2100"
    assert_nil request.duration_in_days
  end

  test "dates outside the supported calendar years are rejected" do
    request = LeaveRequest.new(employee: @employee, leave_type: @leave_type,
      starts_on: Date.new(1999, 12, 31), ends_on: Date.new(2101, 1, 1))

    assert_not request.valid?
    assert_includes request.errors[:starts_on], "должна быть между 01.01.2000 и 31.12.2100"
    assert_includes request.errors[:ends_on], "должна быть между 01.01.2000 и 31.12.2100"
  end

  test "database rejects non-finite dates without model validation" do
    request = create_request

    assert_raises(ActiveRecord::StatementInvalid) do
      LeaveRequest.transaction(requires_new: true) do
        LeaveRequest.where(id: request.id).update_all(starts_on: Arel.sql("'infinity'::date"))
      end
    end
  end

  test "database rejects unsupported years without model validation" do
    request = create_request

    assert_raises(ActiveRecord::StatementInvalid) do
      LeaveRequest.transaction(requires_new: true) do
        LeaveRequest.where(id: request.id).update_all(ends_on: Date.new(2101, 1, 1))
      end
    end
  end

  test "inactive leave type cannot be requested" do
    @leave_type.update!(active: false)

    request = LeaveRequest.new(employee: @employee, leave_type: @leave_type,
      starts_on: Date.new(2026, 10, 10), ends_on: Date.new(2026, 10, 10))

    assert_not request.valid?
    assert_includes request.errors[:leave_type], "недоступен для оформления"
  end

  test "manager can approve a pending request" do
    request = create_request

    request.approve!(by: @manager, comment: "Coverage arranged")

    assert_predicate request, :approved?
    assert_equal @manager, request.reviewer
    assert_equal "Coverage arranged", request.review_comment
    assert_not_nil request.reviewed_at
    assert_predicate request.events.order(:id).last, :approved?
  end

  test "employee cannot approve their own request" do
    request = create_request

    error = assert_raises(LeaveRequest::InvalidTransition) do
      request.approve!(by: @employee)
    end

    assert_equal "employees cannot review their own requests", error.message
    assert_predicate request.reload, :pending?
  end

  test "reviewed request cannot be reviewed again" do
    request = create_request
    request.reject!(by: @manager)

    assert_raises(LeaveRequest::InvalidTransition) do
      request.approve!(by: @manager)
    end
    assert_predicate request.reload, :rejected?
  end

  test "approved request can be cancelled" do
    request = create_request
    request.approve!(by: @manager)

    request.cancel!

    assert_predicate request, :cancelled?
  end

  test "active requests cannot overlap including period boundaries" do
    create_request
    request = LeaveRequest.new(employee: @employee, leave_type: @leave_type,
      starts_on: Date.new(2026, 10, 14), ends_on: Date.new(2026, 10, 16))

    assert_not request.valid?
    assert_includes request.errors[:base], "Период пересекается с другой активной заявкой"
  end

  test "cancelled request does not block same period" do
    existing_request = create_request
    existing_request.cancel!

    request = LeaveRequest.new(employee: @employee, leave_type: @leave_type,
      starts_on: existing_request.starts_on, ends_on: existing_request.ends_on)

    assert request.valid?
  end

  test "rejected request does not block same period" do
    existing_request = create_request
    existing_request.reject!(by: @manager)

    request = LeaveRequest.new(employee: @employee, leave_type: @leave_type,
      starts_on: existing_request.starts_on, ends_on: existing_request.ends_on)

    assert request.valid?
  end

  test "database prevents overlapping active requests" do
    existing_request = create_request

    assert_raises(ActiveRecord::StatementInvalid) do
      LeaveRequest.insert_all!([ {
        employee_id: @employee.id, leave_type_id: @leave_type.id,
        starts_on: existing_request.ends_on, ends_on: existing_request.ends_on + 2.days,
        status: LeaveRequest.statuses.fetch(:pending), created_at: Time.current,
        updated_at: Time.current
      } ])
    end
  end

  test "duration includes ordinary weekends" do
    request = LeaveRequest.new(employee: @employee, leave_type: @leave_type,
      starts_on: Date.new(2026, 10, 5), ends_on: Date.new(2026, 10, 11))

    assert_equal 7, request.duration_in_days
  end

  test "duration handles the full supported range and counts holidays across years" do
    request = LeaveRequest.new(employee: @employee, leave_type: @leave_type,
      starts_on: Date.new(2000, 1, 1), ends_on: Date.new(2100, 12, 31))

    assert_predicate request, :valid?
    assert_equal 36_890, request.duration_in_days

    @leave_type.update!(holiday_handling: :exclude_public_holidays)
    assert_equal 35_476, request.duration_in_days
  end

  test "duration excludes federal holidays when leave type requires it" do
    @leave_type.update!(holiday_handling: :exclude_public_holidays)
    request = LeaveRequest.new(employee: @employee, leave_type: @leave_type,
      starts_on: Date.new(2026, 1, 1), ends_on: Date.new(2026, 1, 10))

    assert_equal 2, request.duration_in_days
  end

  test "request with zero duration is invalid" do
    @leave_type.update!(holiday_handling: :exclude_public_holidays)
    request = LeaveRequest.new(employee: @employee, leave_type: @leave_type,
      starts_on: Date.new(2026, 1, 1), ends_on: Date.new(2026, 1, 8))

    assert_not request.valid?
    assert_includes request.errors[:base],
      "На эти даты оформить «Annual leave» не получится: весь выбранный период " \
      "приходится на праздничные дни, которые не засчитываются в отпуск. Если вы " \
      "отсутствуете из-за болезни, выберите «Больничный». В остальных случаях " \
      "укажите другие даты"
  end

  test "holidays produce positive duration when leave type includes them" do
    request = LeaveRequest.new(employee: @employee, leave_type: @leave_type,
      starts_on: Date.new(2026, 1, 1), ends_on: Date.new(2026, 1, 8))

    assert request.valid?
    assert_equal 8, request.duration_in_days
  end

  test "duration includes federal holidays when leave type requires it" do
    request = LeaveRequest.new(employee: @employee, leave_type: @leave_type,
      starts_on: Date.new(2026, 1, 1), ends_on: Date.new(2026, 1, 10))

    assert_equal 10, request.duration_in_days
  end

  test "morning and afternoon on same date do not overlap" do
    LeaveRequest.create!(employee: @employee, leave_type: @leave_type,
      starts_on: Date.new(2026, 12, 1), ends_on: Date.new(2026, 12, 1),
      start_part: :morning, end_part: :morning)
    request = LeaveRequest.new(employee: @employee, leave_type: @leave_type,
      starts_on: Date.new(2026, 12, 1), ends_on: Date.new(2026, 12, 1),
      start_part: :afternoon, end_part: :afternoon)

    assert request.valid?
    assert_equal 0.5, request.duration_in_days
  end

  test "same half day overlaps" do
    LeaveRequest.create!(employee: @employee, leave_type: @leave_type,
      starts_on: Date.new(2026, 12, 1), ends_on: Date.new(2026, 12, 1),
      start_part: :morning, end_part: :morning)
    request = LeaveRequest.new(employee: @employee, leave_type: @leave_type,
      starts_on: Date.new(2026, 12, 1), ends_on: Date.new(2026, 12, 1),
      start_part: :morning, end_part: :morning)

    assert_not request.valid?
  end

  test "database permits different half days and rejects duplicate slot" do
    attributes = {
      employee_id: @employee.id, leave_type_id: @leave_type.id,
      starts_on: Date.new(2026, 12, 1), ends_on: Date.new(2026, 12, 1),
      status: LeaveRequest.statuses.fetch(:pending), created_at: Time.current,
      updated_at: Time.current
    }
    LeaveRequest.insert_all!([ attributes.merge(start_part: 0, end_part: 0) ])
    LeaveRequest.insert_all!([ attributes.merge(start_part: 1, end_part: 1) ])

    assert_raises(ActiveRecord::StatementInvalid) do
      LeaveRequest.insert_all!([ attributes.merge(start_part: 0, end_part: 0) ])
    end
  end

  test "multi-day request can have partial boundaries" do
    request = LeaveRequest.new(employee: @employee, leave_type: @leave_type,
      starts_on: Date.new(2026, 12, 1), ends_on: Date.new(2026, 12, 14),
      start_part: :afternoon, end_part: :morning)

    assert request.valid?
    assert_equal 13, request.duration_in_days
  end

  test "end boundary cannot precede start boundary on the same date" do
    request = LeaveRequest.new(employee: @employee, leave_type: @leave_type,
      starts_on: Date.new(2026, 12, 1), ends_on: Date.new(2026, 12, 1),
      start_part: :afternoon, end_part: :morning)

    assert_not request.valid?
    assert_includes request.errors[:base],
      "Период отсутствия не может начаться после полудня и закончиться до полудня " \
      "того же дня. Выберите окончание «До конца дня» или укажите следующую дату"
    assert_equal 1, request.errors[:base].size
  end

  private

  def create_request
    LeaveRequest.create!(employee: @employee, leave_type: @leave_type,
      starts_on: Date.new(2026, 10, 12), ends_on: Date.new(2026, 10, 14))
  end
end
