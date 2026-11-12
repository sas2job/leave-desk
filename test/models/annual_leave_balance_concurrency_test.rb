require "test_helper"
require "timeout"

class AnnualLeaveBalanceConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "parallel submissions in different calendar years cannot spend the same remaining days" do
    suffix = SecureRandom.hex(6)
    manager = User.create!(name: "Concurrent Manager", email_address: "balance-manager-#{suffix}@example.test", password: "test-password", role: :manager)
    employee = User.create!(name: "Concurrent Employee", email_address: "balance-employee-#{suffix}@example.test", password: "test-password", manager:)
    type = LeaveType.find_or_create_by!(code: "ANNUAL") { |item| item.name = "Ежегодный отпуск"; item.holiday_handling = :exclude_public_holidays }
    created_calendar_ids = []
    [ 2026, 2027 ].each do |year|
      next if FederalCalendar.exists?(year:)
      calendar = FederalCalendar.create!(year:, legal_basis: "Тест", public_holidays: RussianFederalHoliday.fixed_dates_for(year))
      created_calendar_ids << calendar.id
    end
    account = configure_annual_year(employee)
    ready = Queue.new
    start = Queue.new
    threads = [ [ Date.new(2026, 10, 15), Date.new(2026, 11, 3) ], [ Date.new(2027, 1, 10), Date.new(2027, 1, 29) ] ].map do |first, last|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          request = LeaveRequest.new(employee: User.find(employee.id), leave_type: type, starts_on: first, ends_on: last)
          ready << true
          start.pop
          request.submit
        end
      end
    end
    Timeout.timeout(10) do
      2.times { ready.pop }
      2.times { start << true }
      results = threads.map(&:value)
      assert_equal 1, results.count(true)
      assert_equal 1, employee.leave_requests.count
      assert_equal 20 * 1440, account.reload.reserved_minutes
      assert_equal 8 * 1440, account.available_minutes
    end
  ensure
    threads&.each { |thread| thread.join(1) }
    if employee
      requests = LeaveRequest.where(employee_id: employee.id)
      events = LeaveRequestEvent.where(leave_request_id: requests.select(:id))
      Notification.where(leave_request_event_id: events.select(:id)).delete_all
      events.delete_all
      AnnualLeaveBooking.where(leave_request_id: requests.select(:id)).delete_all
      requests.delete_all
      AnnualLeaveYear.where(employee_id: employee.id).delete_all
      employee.delete
    end
    manager&.delete
    FederalCalendar.where(id: created_calendar_ids).delete_all if created_calendar_ids
  end
end
