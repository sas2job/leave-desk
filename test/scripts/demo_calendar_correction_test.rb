require "test_helper"
require Rails.root.join("script/correct_demo_calendar_2026")

class DemoCalendarCorrectionTest < ActiveSupport::TestCase
  setup do
    load Rails.root.join("db/seeds.rb")
    @manager = User.create!(name: "Demo Manager", email_address: "correction-manager@leave-desk.test",
      password: "test-password", role: :manager)
    @annual = LeaveType.find_by!(code: "ANNUAL")
    @employees = []
    @sources = []
    travel_to Time.zone.local(2026, 1, 1, 12) do
      21.times do |index|
        employee = User.create!(name: "Demo Employee", email_address: "correction-#{index}@leave-desk.test",
          password: "test-password", manager: @manager,
          birthday_on: Date.new(1990, index % 12 + 1, (index * 3) % 27 + 1))
        starts_on = Date.new(2026, index % 12 + 1, 10 + index % 4)
        @employees << employee
        @sources << create_approved(employee, starts_on, starts_on + 6)
      end
    end
    @correction = DemoCalendarCorrection2026.new
  end

  test "preview is repeatable read only and removes the birthday month pattern" do
    counts = [ LeaveRequest.count, LeaveRequestEvent.count, Notification.count ]
    result = @correction.preview

    assert_equal result, @correction.preview
    assert_equal counts, [ LeaveRequest.count, LeaveRequestEvent.count, Notification.count ]
    assert_equal 21, result[:before][:birthday_month_matches]
    assert_operator result[:after][:birthday_month_matches], :<=, 4
    assert_operator result[:after][:birthdays_inside_leave], :<=, 2
    assert_equal (1..12).to_a, result[:after][:months]
    assert_operator result[:after][:overlap_days], :>, 0
    assert_operator result[:after][:max_daily_absent], :>=, 2
    assert_match(/\A[a-f0-9]{64}\z/, result[:plan_digest])
  end

  test "correction preserves originals and duration and is idempotent" do
    future = create_approved(@employees.first, Date.new(2027, 6, 1), Date.new(2027, 6, 7))
    future_attributes = future.attributes
    birthdays = User.order(:id).pluck(:id, :birthday_on)
    snapshots = @sources.to_h do |source|
      [ source.id, { dates: [ source.starts_on, source.ends_on ], reviewer: [ source.reviewer_id, source.reviewed_at ],
        events: source.events.order(:id).pluck(:id), duration: source.duration_in_days } ]
    end
    digest = @correction.preview.fetch(:plan_digest)
    original_time = Time.current
    result = @correction.apply!(expected_digest: digest)

    assert result[:applied]
    assert_equal 21, result[:preserved_originals]
    assert_equal original_time, Time.current
    assert_equal birthdays, User.order(:id).pluck(:id, :birthday_on)
    assert_equal future_attributes, future.reload.attributes
    @sources.each do |source|
      snapshot = snapshots.fetch(source.id)
      source.reload
      assert_predicate source, :cancelled?
      assert_equal snapshot[:dates], [ source.starts_on, source.ends_on ]
      assert_equal snapshot[:reviewer], [ source.reviewer_id, source.reviewed_at ]
      assert_equal snapshot[:events], source.events.order(:id).limit(snapshot[:events].size).pluck(:id)
      assert_equal "cancelled", source.events.order(:id).last.event_type
      replacement = LeaveRequest.find_by!(employee_comment: "#{DemoCalendarCorrection2026::MARKER}#{source.id}; пакет #{@sources.size}")
      assert_predicate replacement, :approved?
      assert_equal snapshot[:duration], replacement.duration_in_days
      assert_equal %w[created approved], replacement.events.order(:id).pluck(:event_type)
    end
    counts = [ LeaveRequest.count, LeaveRequestEvent.count, Notification.count, LeaveLegalReview.count ]
    assert @correction.apply!(expected_digest: digest)[:already_applied]
    assert_equal counts, [ LeaveRequest.count, LeaveRequestEvent.count, Notification.count, LeaveLegalReview.count ]
  end

  test "stale plans and non demo accounts are rejected before changes" do
    digest = @correction.preview.fetch(:plan_digest)
    @employees.first.update!(birthday_on: Date.new(1990, 6, 15))
    assert_raises(DemoCalendarCorrection2026::UnsafeData) { @correction.apply!(expected_digest: digest) }
    assert @sources.all? { |source| source.reload.approved? }

    User.create!(name: "External Account", email_address: "external@example.test", password: "test-password")
    assert_raises(DemoCalendarCorrection2026::UnsafeData) { @correction.preview }
    assert @sources.all? { |source| source.reload.approved? }
  end

  test "historical partial annual leave is preserved without conversion" do
    legacy = @sources.first
    LeaveRequest.where(id: legacy.id).update_all(legal_kind: 0, start_minute: 540, end_minute: 540)
    attributes = legacy.reload.attributes
    events = legacy.events.order(:id).pluck(:id)
    preview = @correction.preview

    assert_equal 20, preview[:correction_requests]
    assert_equal 1, preview[:unchanged_legacy]
    @correction.apply!(expected_digest: preview.fetch(:plan_digest))
    assert_equal attributes, legacy.reload.attributes
    assert_equal events, legacy.events.order(:id).pluck(:id)
    assert @correction.preview[:already_applied]
    assert_equal 20, @correction.preview[:corrected_requests]
  end

  test "an employee without approved annual leave is not given a new request" do
    missing = @sources.first
    missing.cancel!(by: missing.employee)
    preview = @correction.preview

    assert_equal 1, preview[:without_approved_annual]
    assert_equal 20, preview[:correction_requests]
    @correction.apply!(expected_digest: preview.fetch(:plan_digest))
    assert_equal [ missing.id ], missing.employee.leave_requests.pluck(:id)
    assert_predicate missing.reload, :cancelled?
    assert @correction.preview[:already_applied]
  end

  test "an explicitly selected demo roster leaves other employees unchanged" do
    external = User.create!(name: "External Account", email_address: "outside@example.test", password: "test-password")
    external_attributes = external.attributes
    @employees[1].update!(role: :manager)
    other = @sources.first
    attributes = other.attributes
    events = other.events.order(:id).pluck(:id)
    correction = DemoCalendarCorrection2026.new(expected_employees: 20,
      employee_emails: @employees.drop(1).map(&:email_address))
    preview = correction.preview

    assert_equal 20, preview[:employees]
    assert_equal 20, preview[:correction_requests]
    correction.apply!(expected_digest: preview.fetch(:plan_digest))
    assert_equal attributes, other.reload.attributes
    assert_equal events, other.events.order(:id).pluck(:id)
    assert_equal external_attributes, external.reload.attributes
    assert correction.preview[:already_applied]
  end

  test "a failure after creating replacements rolls back the whole correction" do
    failing_class = Class.new(DemoCalendarCorrection2026) do
      private

      def create_replacement(entry)
        super
        raise "Simulated failure"
      end
    end
    correction = failing_class.new
    digest = correction.preview.fetch(:plan_digest)
    counts = [ LeaveRequest.count, LeaveRequestEvent.count, Notification.count, LeaveLegalReview.count ]

    assert_raises(RuntimeError) { correction.apply!(expected_digest: digest) }
    assert_equal counts, [ LeaveRequest.count, LeaveRequestEvent.count, Notification.count, LeaveLegalReview.count ]
    assert @sources.all? { |source| source.reload.approved? }
  end

  private

  def create_approved(employee, starts_on, ends_on)
    request = LeaveRequest.create!(employee:, leave_type: @annual, starts_on:, ends_on:)
    request.approve!(by: @manager, legal_review: { conditions_confirmed: true,
      working_year_starts_on: starts_on.beginning_of_year, working_year_ends_on: starts_on.end_of_year,
      entitlement_days: 28 })
    request
  end
end
