require "test_helper"
require "timeout"

module Manager
  class LeaveRequestReassignmentConcurrencyTest < ActionDispatch::IntegrationTest
    self.use_transactional_tests = false

    setup do
      suffix = SecureRandom.hex(6)
      @former_manager = create_user("former-#{suffix}@example.test", role: :manager)
      @new_manager = create_user("new-#{suffix}@example.test", role: :manager)
      @employee = create_user("employee-#{suffix}@example.test", manager: @former_manager)
      @leave_type = LeaveType.create!(name: "Annual leave", code: "TEST_#{suffix.upcase}")
      @leave_request = LeaveRequest.create!(employee: @employee, leave_type: @leave_type,
        starts_on: Date.new(2026, 11, 1), ends_on: Date.new(2026, 11, 2))
    end

    teardown do
      user_ids = [ @employee, @former_manager, @new_manager ].compact.map(&:id)
      Notification.where(recipient_id: user_ids).delete_all
      Session.where(user_id: user_ids).delete_all
      LeaveRequestEvent.where(leave_request_id: @leave_request.id).delete_all if @leave_request
      @leave_request&.delete
      @leave_type&.delete
      @employee&.delete
      @former_manager&.delete
      @new_manager&.delete
    end

    test "approval loses authority when employee is transferred after lookup" do
      assert_transfer_blocks_former_manager(:approve, :approved)
    end

    test "rejection loses authority when employee is transferred after lookup" do
      assert_transfer_blocks_former_manager(:reject, :rejected)
    end

    test "transfer waits for an in-progress decision holding the employee lock" do
      entered_review = Queue.new
      release_review = Queue.new
      started_transfer = Queue.new
      review_thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          request = LeaveRequest.find(@leave_request.id)
          request.define_singleton_method(:record_event!) do |*args, **kwargs|
            entered_review << true
            release_review.pop
            super(*args, **kwargs)
          end
          request.approve!(by: User.find(@former_manager.id))
        end
      end
      Timeout.timeout(5) { entered_review.pop }
      transfer_thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          employee = User.find(@employee.id)
          started_transfer << true
          employee.update!(manager: @new_manager)
        end
      end
      Timeout.timeout(5) { started_transfer.pop }

      assert_nil transfer_thread.join(0.1)
      release_review << true
      review_thread.value
      transfer_thread.value

      assert_predicate @leave_request.reload, :approved?
      assert_equal @former_manager.id, @leave_request.reviewer_id
      assert_equal @new_manager.id, @employee.reload.manager_id
      assert_predicate @leave_request.events.last, :approved?
    ensure
      release_review&.push(true)
      review_thread&.join(5)
      transfer_thread&.join(5)
    end

    private

    def assert_transfer_blocks_former_manager(action, expected_status)
      sign_in_as(@former_manager)
      original_event_count = @leave_request.events.count
      original_notification_count = Notification.count
      lookup_finished = Queue.new
      transfer_finished = Queue.new
      transfer_thread = Thread.new do
        Timeout.timeout(5) { lookup_finished.pop }
        ActiveRecord::Base.connection_pool.with_connection do
          User.find(@employee.id).update!(manager: @new_manager)
        end
      ensure
        transfer_finished << true
      end
      probe = TracePoint.new(:return) do |event|
        next unless event.defined_class == Manager::LeaveRequestsController &&
          event.method_id == :set_leave_request

        lookup_finished << true
        Timeout.timeout(5) { transfer_finished.pop }
      end

      probe.enable do
        patch public_send("#{action}_manager_leave_request_path", @leave_request),
          params: { review_comment: "Reviewed" }
      end
      transfer_thread.value

      assert_response :not_found
      assert_equal @new_manager.id, @employee.reload.manager_id
      assert_predicate @leave_request.reload, :pending?
      assert_nil @leave_request.reviewer_id
      assert_nil @leave_request.reviewed_at
      assert_nil @leave_request.review_comment
      assert_equal original_event_count, @leave_request.events.count
      assert_equal original_notification_count, Notification.count

      sign_in_as(@new_manager)
      patch public_send("#{action}_manager_leave_request_path", @leave_request)
      assert_redirected_to manager_leave_requests_path
      assert @leave_request.reload.public_send("#{expected_status}?")
      assert_equal @new_manager.id, @leave_request.reviewer_id
      assert_equal original_event_count + 1, @leave_request.events.count
    ensure
      probe&.disable
      lookup_finished&.push(true)
      transfer_thread&.join(5)
    end

    def create_user(email_address, role: :employee, manager: nil)
      User.create!(name: "Example User", email_address:, password: "test-password",
        role:, manager:)
    end
  end
end
