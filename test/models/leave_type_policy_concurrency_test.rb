require "test_helper"
require "timeout"

class LeaveTypePolicyConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    travel_to Date.new(2026, 1, 1)
    suffix = SecureRandom.hex(6)
    @employee = User.create!(name: "Employee", email_address: "employee-#{suffix}@example.test",
      password: "test-password")
    @leave_type = LeaveType.create!(name: "Test leave", code: "TEST_POLICY_#{suffix.upcase}")
    @request = LeaveRequest.new(employee: @employee, leave_type: @leave_type,
      starts_on: Date.new(2026, 1, 1), ends_on: Date.new(2026, 1, 1))
  end

  teardown do
    if @request&.persisted?
      LeaveRequestEvent.where(leave_request_id: @request.id).delete_all
      @request.delete
    end
    @leave_type&.delete
    @employee&.delete
  end

  test "first request prevents concurrent holiday policy change" do
    leave_type = LeaveType.find(@leave_type.id)
    leave_type.holiday_handling = :exclude_public_holidays

    created, changed = run_concurrently(
      first: @request, validation: :leave_type_is_active,
      second: leave_type, first_action: -> { @request.save! },
      second_action: -> { leave_type.save }
    )

    assert created
    assert_not changed
    assert_predicate @leave_type.reload, :include_public_holidays?
    assert_equal 1, @leave_type.leave_requests.count
  end

  test "policy change prevents concurrent first request using stale policy" do
    assert_predicate @request.leave_type, :include_public_holidays?
    leave_type = LeaveType.find(@leave_type.id)
    leave_type.holiday_handling = :exclude_public_holidays

    changed, created = run_concurrently(
      first: leave_type, validation: :holiday_handling_is_unchanged_when_used,
      second: @request, first_action: -> { leave_type.save! },
      second_action: -> { @request.save }
    )

    assert changed
    assert_not created
    assert_predicate @leave_type.reload, :exclude_public_holidays?
    assert_equal 0, @leave_type.leave_requests.count
    assert_predicate @request.errors[:base], :present?
  end

  private

  def run_concurrently(first:, validation:, second:, first_action:, second_action:)
    entered_validation = Queue.new
    release_validation = Queue.new
    started_second_save = Queue.new

    first.define_singleton_method(validation) do
      super()
      entered_validation << true
      release_validation.pop
    end
    second.define_singleton_method(:save) do |**options|
      started_second_save << true
      super(**options)
    end

    first_thread = Thread.new { ActiveRecord::Base.connection_pool.with_connection { first_action.call } }
    Timeout.timeout(5) { entered_validation.pop }
    second_thread = Thread.new { ActiveRecord::Base.connection_pool.with_connection { second_action.call } }
    Timeout.timeout(5) { started_second_save.pop }
    assert_nil second_thread.join(0.1), "concurrent save must wait for the leave type row lock"

    release_validation << true
    [ first_thread.value, second_thread.value ]
  ensure
    release_validation&.push(true)
    first_thread&.join(5)
    second_thread&.join(5)
  end
end
