require "test_helper"
require "timeout"

class FederalCalendarConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  YEAR = 2026

  setup do
    @suffix = SecureRandom.hex(6)
    FederalCalendar.where(year: YEAR).delete_all
    @manager = create_user("manager-#{@suffix}@example.test", role: :manager)
    @employee = create_user("employee-#{@suffix}@example.test", manager: @manager)
    @administrator = create_user("administrator-#{@suffix}@example.test", role: :administrator)
    @leave_type = LeaveType.create!(name: "Annual leave", code: "CAL_#{@suffix.upcase}",
      holiday_handling: :exclude_public_holidays)
  end

  teardown do
    request_ids = LeaveRequest.where(employee_id: @employee&.id).select(:id)
    event_ids = LeaveRequestEvent.where(leave_request_id: request_ids).select(:id)
    Notification.where(leave_request_event_id: event_ids).delete_all
    LeaveRequestEvent.where(leave_request_id: request_ids).delete_all
    LeaveRequest.where(id: request_ids).delete_all
    FederalCalendar.where(year: YEAR).delete_all
    @leave_type&.delete
    @employee&.delete
    @manager&.delete
    @administrator&.delete
  end

  test "first calendar creation waits for fallback request snapshot" do
    request_entered_calculation = Queue.new
    release_request = Queue.new
    calendar_started = Queue.new
    request = build_request
    request.define_singleton_method(:store_duration) do
      request_entered_calculation << true
      release_request.pop
      super()
    end

    request_thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection { request.save! }
    end
    Timeout.timeout(5) { request_entered_calculation.pop }
    calendar_thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        calendar_started << true
        create_calendar
      end
    end
    Timeout.timeout(5) { calendar_started.pop }

    assert_nil calendar_thread.join(0.1)
    release_request << true
    request_thread.value
    calendar_thread.value

    assert_predicate request.reload, :calendar_unverified?
    assert_equal 2, request.duration_in_days
    assert_equal %w[created calendar_unverified], request.events.order(:id).pluck(:event_type)
    assert_equal 1, Notification.where(recipient: @administrator,
      leave_request_event: request.events.calendar_unverified.first).count
  ensure
    release_request&.push(true)
    request_thread&.join(5)
    calendar_thread&.join(5)
  end

  test "request waits for first calendar creation and uses committed calendar" do
    calendar_has_year_lock = Queue.new
    release_calendar = Queue.new
    request_started = Queue.new
    calendar = build_calendar
    pause_calendar_after_year_lock(calendar, calendar_has_year_lock, release_calendar)

    calendar_thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection { calendar.save! }
    end
    Timeout.timeout(5) { calendar_has_year_lock.pop }
    request = build_request
    request_thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        request_started << true
        request.save!
      end
    end
    Timeout.timeout(5) { request_started.pop }

    assert_nil request_thread.join(0.1)
    release_calendar << true
    calendar_thread.value
    request_thread.value

    assert_not request.reload.calendar_unverified?
    assert_equal 3, request.duration_in_days
    assert_equal [ "created" ], request.events.pluck(:event_type)
    assert_empty @administrator.notifications
  ensure
    release_calendar&.push(true)
    calendar_thread&.join(5)
    request_thread&.join(5)
  end

  test "request waits for calendar update and uses committed holidays" do
    calendar = FederalCalendar.create!(year: YEAR, legal_basis: "Initial calendar",
      public_holidays: RussianFederalHoliday.fixed_dates_for(YEAR))
    calendar.assign_attributes(legal_basis: "Updated calendar",
      public_holidays: [ Date.new(YEAR, 1, 1) ])
    calendar_has_year_lock = Queue.new
    release_calendar = Queue.new
    request_started = Queue.new
    pause_calendar_after_year_lock(calendar, calendar_has_year_lock, release_calendar)

    calendar_thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection { calendar.save! }
    end
    Timeout.timeout(5) { calendar_has_year_lock.pop }
    request = build_request
    request_thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        request_started << true
        request.save!
      end
    end
    Timeout.timeout(5) { request_started.pop }

    assert_nil request_thread.join(0.1)
    release_calendar << true
    calendar_thread.value
    request_thread.value

    assert_not request.reload.calendar_unverified?
    assert_equal 3, request.duration_in_days
  ensure
    release_calendar&.push(true)
    calendar_thread&.join(5)
    request_thread&.join(5)
  end

  private

  def build_request
    LeaveRequest.new(employee: @employee, leave_type: @leave_type,
      starts_on: Date.new(YEAR, 6, 11), ends_on: Date.new(YEAR, 6, 13))
  end

  def build_calendar
    FederalCalendar.new(year: YEAR, legal_basis: "Configured calendar",
      public_holidays: [ Date.new(YEAR, 1, 1) ])
  end

  def create_calendar
    build_calendar.save!
  end

  def pause_calendar_after_year_lock(calendar, entered, release)
    calendar.define_singleton_method(:with_year_lock_for_save) do |&save|
      self.class.with_year_lock(year) do
        entered << true
        release.pop
        save.call
      end
    end
  end

  def create_user(email_address, role: :employee, manager: nil)
    User.create!(name: "Example User", email_address:, password: "test-password",
      role:, manager:)
  end
end
