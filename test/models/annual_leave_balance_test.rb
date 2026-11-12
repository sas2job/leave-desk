require "test_helper"

class AnnualLeaveBalanceTest < ActiveSupport::TestCase
  setup do
    @administrator = User.create!(name: "Balance Admin", email_address: "balance-admin@example.test", password: "test-password", role: :administrator)
    @manager = User.create!(name: "Balance Manager", email_address: "balance-manager@example.test", password: "test-password", role: :manager)
    @employee = User.create!(name: "Balance Employee", email_address: "balance-employee@example.test", password: "test-password", manager: @manager)
    @annual = LeaveType.find_or_create_by!(code: "ANNUAL") { |type| type.name = "Ежегодный отпуск"; type.holiday_handling = :exclude_public_holidays }
    FederalCalendar.find_or_create_by!(year: 2026) { |calendar| calendar.legal_basis = "Тест"; calendar.public_holidays = RussianFederalHoliday.fixed_dates_for(2026) }
  end

  test "fifty day request cannot be sent against twenty eight days and leaves no records" do
    year = configure_annual_year(@employee)
    request = build_request(Date.new(2026, 11, 12), Date.new(2026, 12, 31))
    assert_no_difference [ "LeaveRequest.count", "AnnualLeaveBooking.count", "Notification.count", "LeaveRequestEvent.count" ] do
      assert_not request.submit
    end
    assert_match(/Недостаточно/, request.errors.full_messages.join)
    assert_equal 28 * 1440, year.reload.available_minutes
  end

  test "missing balance is explicit and other types remain available" do
    request = build_request
    assert_not request.submit
    assert_match(/не настроен/, request.errors.full_messages.join)
    sick = LeaveType.find_or_create_by!(code: "SICK") { |type| type.name = "Болезнь" }
    assert LeaveRequest.new(employee: @employee, leave_type: sick, starts_on: Date.new(2026, 11, 1), ends_on: Date.new(2026, 11, 3)).submit
  end

  test "pending requests reserve balance and approval does not charge twice" do
    year = configure_annual_year(@employee)
    request = build_request
    assert request.submit, request.errors.full_messages.to_sentence
    assert_equal 21 * 1440, year.reload.available_minutes
    assert_equal 7 * 1440, year.reserved_minutes
    request.approve!(by: @manager, legal_review: review)
    assert_equal 21 * 1440, year.reload.available_minutes
    assert_equal 0, year.reserved_minutes
    assert_equal 7 * 1440, year.committed_minutes
  end

  test "separate requests cannot overbook the same balance" do
    year = configure_annual_year(@employee)
    first = build_request(Date.new(2026, 10, 15), Date.new(2026, 11, 3))
    assert first.submit
    second = build_request(Date.new(2026, 12, 1), Date.new(2026, 12, 20))
    assert_not second.submit
    assert_equal 20 * 1440, year.reload.reserved_minutes
  end

  test "carryover can fund a request over twenty eight days oldest year first" do
    previous = configure_annual_year(@employee, year: 2025)
    current = configure_annual_year(@employee)
    request = build_request(Date.new(2026, 11, 12), Date.new(2026, 12, 31))
    assert request.submit, request.errors.full_messages.join
    assert_equal 28 * 1440, previous.reload.reserved_minutes
    assert_equal 22 * 1440, current.reload.reserved_minutes
    assert_equal 6 * 1440, current.available_minutes
  end

  test "future work year cannot fund an earlier request" do
    configure_annual_year(@employee, year: 2027)
    assert_not build_request.submit
  end

  test "rejection and pre start cancellation return reserved and approved days" do
    year = configure_annual_year(@employee)
    request = build_request
    request.submit
    request.reject!(by: @manager)
    assert_equal 28 * 1440, year.reload.available_minutes
    request = build_request
    request.submit
    request.approve!(by: @manager, legal_review: review)
    request.cancel!(by: @employee)
    assert_equal 28 * 1440, year.reload.available_minutes
    assert request.annual_leave_bookings.all?(&:booking_released?)
  end

  test "cancelling after start retains used days" do
    year = configure_annual_year(@employee)
    travel_to Time.zone.local(2026, 11, 10, 12) do
      request = build_request
      request.submit
      request.approve!(by: @manager, legal_review: review)
      travel_to Time.zone.local(2026, 11, 12, 12)
        request.cancel!(by: @employee)
        assert_equal 3 * 1440, request.reload.annual_cancelled_used_minutes
        assert_equal 3 * 1440, year.reload.committed_minutes
        assert_equal 25 * 1440, year.available_minutes
    end
  end

  test "recall refunds only unused part" do
    year = configure_annual_year(@employee)
    request = build_request(Date.new(2026, 10, 15), Date.new(2026, 10, 28))
    request.submit
    request.approve!(by: @manager, legal_review: review)
    travel_to Time.zone.local(2026, 10, 20, 12) do
      recall = LeaveRecall.propose!(leave_request: request, by: @manager, return_on: Date.new(2026, 10, 23), reason: "Рабочая задача", eligibility_confirmed: true)
      recall.consent!(by: @employee, remainder_option: :next_work_year)
      recall.confirm!(by: @manager, order_number: "TEST", order_on: Date.new(2026, 10, 20), consent_reference: "Подтверждение", eligibility_confirmed: true)
    end
    assert_equal 8 * 1440, year.reload.committed_minutes
    assert_equal 20 * 1440, year.available_minutes
  end

  test "legacy pending request is checked on approval and historic approvals are not guessed" do
    year = configure_annual_year(@employee)
    request = build_request(Date.new(2026, 11, 12), Date.new(2026, 12, 31))
    request.save!
    assert_raises(ActiveRecord::RecordInvalid) { request.approve!(by: @manager, legal_review: review) }
    assert_predicate request.reload, :pending?
    assert_equal 28 * 1440, year.reload.available_minutes
    assert_not request.annual_leave_bookings.exists?
  end

  test "failed legal review rolls back reservation" do
    year = configure_annual_year(@employee)
    request = build_request.tap(&:save!)
    assert_raises(ActiveRecord::RecordInvalid) { request.approve!(by: @manager, legal_review: {}) }
    assert_equal 28 * 1440, year.reload.available_minutes
    assert_not request.annual_leave_bookings.exists?
  end

  test "admin adjustments preserve history and cannot consume pending reservations" do
    year = configure_annual_year(@employee)
    build_request.submit
    assert_raises(ActiveRecord::RecordInvalid) do
      year.revise!(by: @administrator, entitlement_days: 28, opening_used_days: "22", reason: "Сверка")
    end
    assert_equal 0, year.reload.opening_used_minutes
    assert_equal 0, year.annual_leave_adjustments.count
    year.revise!(by: @administrator, entitlement_days: 28, opening_used_days: "3.5", reason: "Сверка архива")
    assert_equal 17.5 * 1440, year.reload.available_minutes
    adjustment = year.annual_leave_adjustments.sole
    assert_equal @administrator, adjustment.actor
    assert_equal 0, adjustment.previous_opening_used_minutes
    assert_not adjustment.destroy
    assert_raises(LeaveRequest::ReviewNotAuthorized) { year.revise!(by: @employee, entitlement_days: 90, opening_used_days: "0", reason: "Попытка") }
  end

  test "database prevents overlapping years negative capacity and negative balances" do
    year = configure_annual_year(@employee)
    assert_raises(ActiveRecord::StatementInvalid) do
      AnnualLeaveYear.transaction(requires_new: true) { year.update_columns(reserved_minutes: 29 * 1440) }
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      AnnualLeaveYear.transaction(requires_new: true) { year.update_columns(opening_used_minutes: -1) }
    end
    duplicate = year.reload.attributes.except("id", "created_at", "updated_at")
    assert_raises(ActiveRecord::StatementInvalid) do
      AnnualLeaveYear.transaction(requires_new: true) { AnnualLeaveYear.insert_all!([ duplicate ]) }
    end
  end

  test "profile supports twenty eight thirty minors and irregular work without changing existing credits" do
    assert_equal 28, @employee.annual_default_days
    year = configure_annual_year(@employee)
    @employee.update!(extended_annual_leave: true, annual_leave_basis: "Установленная гарантия")
    assert_equal 30, @employee.annual_default_days
    @employee.update!(annual_additional_days: 3)
    assert_equal 33, @employee.annual_default_days
    assert_not @employee.update(annual_additional_days: 2)
    @employee.reload
    @employee.update!(birthday_on: Date.new(2010, 1, 1))
    assert_equal 34, @employee.annual_default_days
    assert_equal 28, year.reload.entitlement_days
    assert_raises(ActiveRecord::RecordInvalid) { configure_annual_year(@employee, year: 2027, days: 28) }
  end

  test "calendar reconciliation cannot overdraw a reserved balance" do
    year = configure_annual_year(@employee, used: 22)
    request = build_request(Date.new(2026, 11, 1), Date.new(2026, 11, 7))
    assert request.submit
    assert_equal 6, request.duration_in_days
    calendar = FederalCalendar.find_by!(year: 2026)
    calendar.update!(public_holidays: calendar.public_holidays - [ Date.new(2026, 11, 4) ])
    assert_predicate request.reload, :calendar_unverified?
    assert_raises(ActiveRecord::RecordInvalid) { request.reconcile_calendar!(by: @administrator) }
    assert_equal 6, request.reload.duration_in_days
    assert_predicate request, :calendar_unverified?
    assert_equal 6 * 1440, year.reload.reserved_minutes
    assert_equal 0, year.available_minutes
  end

  test "former manager cannot adjust a balance after staff reassignment" do
    year = configure_annual_year(@employee)
    replacement = User.create!(name: "New Manager", email_address: "balance-new-manager@example.test", password: "test-password", role: :manager)
    @employee.update!(manager: replacement)
    assert_raises(LeaveRequest::ReviewNotAuthorized) do
      year.revise!(by: @manager, entitlement_days: 30, opening_used_days: "0", reason: "Основание")
    end
    year.revise!(by: replacement, entitlement_days: 30, opening_used_days: "0", reason: "Основание")
    assert_equal replacement, year.annual_leave_adjustments.sole.actor
  end

  private

  def build_request(first = Date.new(2026, 11, 10), last = Date.new(2026, 11, 16))
    LeaveRequest.new(employee: @employee, leave_type: @annual, starts_on: first, ends_on: last)
  end

  def review
    { conditions_confirmed: true, working_year_starts_on: Date.new(2026, 1, 1), working_year_ends_on: Date.new(2026, 12, 31), entitlement_days: 28 }
  end
end
