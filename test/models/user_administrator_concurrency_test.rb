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
end
