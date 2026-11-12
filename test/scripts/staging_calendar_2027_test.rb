require "test_helper"
require Rails.root.join("script/seed_staging_calendar_2027")

class StagingCalendar2027Test < ActiveSupport::TestCase
  setup do
    load Rails.root.join("db/seeds.rb")
    @manager = User.create!(name: "Staging Manager", email_address: "staging-manager@leave-desk.test",
      password: "test-password", role: :manager)
    @employees = 22.times.map do |index|
      User.create!(name: "Staging Employee", email_address: "staging-#{index}@leave-desk.test",
        password: "test-password", manager: @manager,
        birthday_on: index < 2 ? nil : DemoBirthdayDates.for_index(index % 20))
    end
    @generator = StagingCalendar2027.new
  end

  test "preview validates generation and rolls back all demo data" do
    counts = [ LeaveRequest.count, LeaveRequestEvent.count, Notification.count, LeaveLegalReview.count ]
    profiles = @employees.map { |employee| employee.attributes.slice("id", "birthday_on", "updated_at") }
    original_time = Time.current
    preview = @generator.preview

    assert_equal preview, @generator.preview
    assert_equal original_time, Time.current
    assert_equal 66, preview[:added_requests]
    assert_equal 2, preview[:filled_birthdays]
    assert_equal 22, preview[:after][:employees_with_two_approved_annual]
    assert_equal 22, preview[:after][:employees_with_approved_birthday]
    assert_equal (1..12).to_a, preview[:after][:overlap_months]
    assert_operator preview[:after][:max_daily_absent], :>=, 4
    assert_equal counts, [ LeaveRequest.count, LeaveRequestEvent.count, Notification.count, LeaveLegalReview.count ]
    assert_equal profiles, @employees.map { |employee| employee.reload.attributes.slice("id", "birthday_on", "updated_at") }
  end

  test "apply preserves reference calendars existing leave and repeat runs" do
    employee = @employees.last
    employee.update!(birthday_on: Date.new(1990, 8, 10))
    annual = LeaveType.find_by!(code: "ANNUAL")
    configure_annual_year(employee, year: 2027)
    existing = LeaveRequest.create!(employee:, leave_type: annual, starts_on: Date.new(2027, 2, 10), ends_on: Date.new(2027, 2, 16))
    existing.approve!(by: @manager, legal_review: { conditions_confirmed: true,
      working_year_starts_on: Date.new(2027, 1, 1), working_year_ends_on: Date.new(2027, 12, 31), entitlement_days: 28 })
    attributes = existing.attributes
    calendar = FederalCalendar.find_by!(year: 2027)
    calendar.update!(legal_basis: "Администратор проверил календарь")
    calendar_attributes = calendar.attributes
    preview = @generator.preview
    result = @generator.apply!(expected_digest: preview.fetch(:plan_digest))

    assert result[:applied]
    assert_equal 65, result[:added_requests]
    assert_equal attributes, existing.reload.attributes
    assert_equal calendar_attributes, calendar.reload.attributes
    assert_equal 22, result[:after][:employees_with_two_approved_annual]
    assert_equal 22, result[:after][:employees_with_approved_birthday]
    counts = [ LeaveRequest.count, LeaveRequestEvent.count, Notification.count, LeaveLegalReview.count ]
    assert @generator.preview[:already_applied]
    assert @generator.apply!(expected_digest: preview.fetch(:plan_digest))[:already_applied]
    assert_equal counts, [ LeaveRequest.count, LeaveRequestEvent.count, Notification.count, LeaveLegalReview.count ]
  end

  test "wrong plan digest rolls back generation and profile fills" do
    counts = [ LeaveRequest.count, LeaveRequestEvent.count, Notification.count ]
    assert_raises(StagingCalendar2027::UnsafeData) { @generator.apply!(expected_digest: "0" * 64) }
    assert_equal counts, [ LeaveRequest.count, LeaveRequestEvent.count, Notification.count ]
    assert_equal 2, @employees.count { |employee| employee.reload.birthday_on.nil? }
  end

  test "missing manager prevents writes" do
    @employees.first.update!(manager: nil)
    counts = [ LeaveRequest.count, LeaveRequestEvent.count, Notification.count ]

    assert_raises(StagingCalendar2027::UnsafeData) { @generator.preview }
    assert_equal counts, [ LeaveRequest.count, LeaveRequestEvent.count, Notification.count ]
  end
end
