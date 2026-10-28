require "test_helper"
require "timeout"

class UserAdministratorConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    suffix = SecureRandom.hex(6)
    @first = User.create!(name: "First Administrator", email_address: "first-#{suffix}@example.test",
      password: "test-password", role: :administrator)
    @second = User.create!(name: "Second Administrator", email_address: "second-#{suffix}@example.test",
      password: "test-password", role: :administrator)
  end

  teardown do
    @first&.delete
    @second&.delete
  end

  test "concurrent removal of the final two administrators preserves one" do
    first = User.find(@first.id)
    second = User.find(@second.id)
    entered_validation = Queue.new
    release_validation = Queue.new
    started_second_save = Queue.new

    first.define_singleton_method(:retain_active_administrator) do
      super()
      entered_validation << true
      release_validation.pop
    end
    second.define_singleton_method(:save) do |**options|
      started_second_save << true
      super(**options)
    end

    first_thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection { first.update(active: false) }
    end
    Timeout.timeout(5) { entered_validation.pop }

    second_thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection { second.update(role: :employee) }
    end
    Timeout.timeout(5) { started_second_save.pop }
    assert_nil second_thread.join(0.1)

    release_validation << true
    assert first_thread.value
    assert_not second_thread.value
    assert_not @first.reload.active?
    assert @second.reload.active?
    assert @second.administrator?
  ensure
    release_validation&.push(true)
    first_thread&.join(5)
    second_thread&.join(5)
  end

  test "stale employee cannot be deactivated after becoming the sole administrator" do
    employee = User.create!(name: "Employee", email_address: "employee-#{SecureRandom.hex(6)}@example.test",
      password: "test-password")
    stale_employee = User.find(employee.id)

    employee.update!(role: :administrator)
    @first.update!(active: false)
    @second.update!(active: false)

    assert_not stale_employee.update(active: false)
    assert_includes stale_employee.errors[:base], "Нельзя удалить последнего активного администратора"
    assert employee.reload.active?
    assert employee.administrator?
  ensure
    employee&.delete
  end

  test "stale inactive administrator cannot be demoted after becoming the sole active administrator" do
    administrator = User.create!(name: "Inactive Administrator",
      email_address: "inactive-#{SecureRandom.hex(6)}@example.test", password: "test-password",
      role: :administrator, active: false)
    stale_administrator = User.find(administrator.id)

    administrator.update!(active: true)
    @first.update!(role: :employee)
    @second.update!(role: :employee)

    assert_not stale_administrator.update(role: :employee)
    assert_includes stale_administrator.errors[:base], "Нельзя удалить последнего активного администратора"
    assert administrator.reload.active?
    assert administrator.administrator?
  ensure
    administrator&.delete
  end
end
