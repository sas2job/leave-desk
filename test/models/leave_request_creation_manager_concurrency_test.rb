require "test_helper"
require "timeout"

class LeaveRequestCreationManagerConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @suffix = SecureRandom.hex(6)
    @former_manager = create_user("former-manager-#{@suffix}@example.test", role: :manager)
    @new_manager = create_user("new-manager-#{@suffix}@example.test", role: :manager)
    @employee = create_user("employee-#{@suffix}@example.test", manager: @former_manager)
    @leave_type = LeaveType.create!(name: "Annual leave", code: "CREATE_#{@suffix.upcase}")
    @calendar = FederalCalendar.create!(year: 2026, legal_basis: "Federal calendar 2026",
      public_holidays: RussianFederalHoliday.fixed_dates_for(2026))
  end

  teardown do
    request_ids = LeaveRequest.where(employee_id: @employee&.id).select(:id)
    event_ids = LeaveRequestEvent.where(leave_request_id: request_ids).select(:id)
    Notification.where(leave_request_event_id: event_ids).delete_all
    LeaveRequestEvent.where(leave_request_id: request_ids).delete_all
    LeaveRequest.where(id: request_ids).delete_all
    @calendar&.delete
    @leave_type&.delete
    @employee&.delete
    @former_manager&.delete
    @new_manager&.delete
  end

  test "creation notifies new manager when reassignment commits first" do
    request = build_request_from_stale_employee
    before_employee_lock = Queue.new
    release_creation = Queue.new
    pause_before_employee_lock(request, before_employee_lock, release_creation)

    creation_thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection { request.save! }
    end
    Timeout.timeout(5) { before_employee_lock.pop }
    User.find(@employee.id).update!(manager: @new_manager)
    release_creation << true
    creation_thread.value

    assert_equal @new_manager.id, @employee.reload.manager_id
    assert_created_notification_for(request, @new_manager)
    assert_empty @former_manager.notifications
  ensure
    release_creation&.push(true)
    creation_thread&.join(5)
  end

  test "reassignment waits when creation locks employee first" do
    request = build_request_from_stale_employee
    creation_entered_event = Queue.new
    release_creation = Queue.new
    reassignment_started = Queue.new
    request.define_singleton_method(:record_created_event) do
      creation_entered_event << true
      release_creation.pop
      super()
    end

    creation_thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection { request.save! }
    end
    Timeout.timeout(5) { creation_entered_event.pop }
    reassignment_thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        reassignment_started << true
        User.find(@employee.id).update!(manager: @new_manager)
      end
    end
    Timeout.timeout(5) { reassignment_started.pop }

    assert_nil reassignment_thread.join(0.1)
    release_creation << true
    creation_thread.value
    reassignment_thread.value

    assert_equal @new_manager.id, @employee.reload.manager_id
    assert_created_notification_for(request, @former_manager)
    assert_empty @new_manager.notifications
  ensure
    release_creation&.push(true)
    creation_thread&.join(5)
    reassignment_thread&.join(5)
  end

  test "creation sees a first manager assignment that commits before employee lock" do
    @employee.update!(manager: nil)
    request = build_request_from_stale_employee
    before_employee_lock = Queue.new
    release_creation = Queue.new
    pause_before_employee_lock(request, before_employee_lock, release_creation)

    creation_thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection { request.save! }
    end
    Timeout.timeout(5) { before_employee_lock.pop }
    User.find(@employee.id).update!(manager: @new_manager)
    release_creation << true
    creation_thread.value

    assert_equal @new_manager.id, @employee.reload.manager_id
    assert_created_notification_for(request, @new_manager)
    assert_empty @former_manager.notifications
  ensure
    release_creation&.push(true)
    creation_thread&.join(5)
  end

  private

  def build_request_from_stale_employee
    employee = User.includes(:manager).find(@employee.id)
    employee.manager
    employee.leave_requests.new(leave_type: @leave_type,
      starts_on: Date.new(2026, 11, 10), ends_on: Date.new(2026, 11, 12))
  end

  def pause_before_employee_lock(request, entered, release)
    request.define_singleton_method(:lock_employee_for_creation) do
      entered << true
      release.pop
      super()
    end
  end

  def assert_created_notification_for(request, manager)
    notification = manager.notifications.joins(:leave_request_event)
      .find_by!(leave_request_events: { leave_request_id: request.id, event_type: :created })
    assert_equal request.id, notification.leave_request.id
  end

  def create_user(email_address, role: :employee, manager: nil)
    User.create!(name: "Example User", email_address:, password: "test-password",
      role:, manager:)
  end
end
