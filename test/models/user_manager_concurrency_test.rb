require "test_helper"
require "timeout"

class UserManagerConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    suffix = SecureRandom.hex(6)
    @manager = User.create!(name: "Manager", email_address: "manager-#{suffix}@example.test",
      password: "test-password", role: :manager)
    @employee = User.create!(name: "Employee", email_address: "employee-#{suffix}@example.test",
      password: "test-password")
  end

  teardown do
    @employee&.delete
    @manager&.delete
  end

  test "first assignment prevents concurrent manager deactivation" do
    employee = User.find(@employee.id)
    employee.manager_id = @manager.id
    manager = User.find(@manager.id)

    assigned, deactivated = run_concurrently(
      first: employee, validation: :manager_is_active_manager,
      second: manager, first_action: -> { employee.save },
      second_action: -> { manager.update(active: false) }
    )

    assert assigned
    assert_not deactivated
    assert @manager.reload.active?
    assert_equal @manager.id, @employee.reload.manager_id
  end

  test "manager demotion prevents concurrent first assignment" do
    manager = User.find(@manager.id)
    employee = User.find(@employee.id)
    employee.manager_id = @manager.id
    assert employee.manager.manager?

    demoted, assigned = run_concurrently(
      first: manager, validation: :role_and_activity_support_direct_reports,
      second: employee, first_action: -> { manager.update(role: :employee) },
      second_action: -> { employee.save }
    )

    assert demoted
    assert_not assigned
    assert @manager.reload.employee?
    assert_nil @employee.reload.manager_id
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
    assert_nil second_thread.join(0.1), "concurrent save must wait for the manager row lock"

    release_validation << true
    [ first_thread.value, second_thread.value ]
  ensure
    release_validation&.push(true)
    first_thread&.join(5)
    second_thread&.join(5)
  end
end
