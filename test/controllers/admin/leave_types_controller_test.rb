require "test_helper"

module Admin
  class LeaveTypesControllerTest < ActionDispatch::IntegrationTest
    setup do
      @administrator = create_user("admin@example.test", role: :administrator)
      @employee = create_user("employee@example.test")
      @leave_type = LeaveType.create!(name: "Annual leave", code: "TEST_ANNUAL")
    end

    test "administrator lists leave types" do
      sign_in_as(@administrator)

      get admin_leave_types_path

      assert_response :success
      assert_select "body", text: /Annual leave/
    end

    test "employee cannot open leave type administration" do
      sign_in_as(@employee)

      get admin_leave_types_path

      assert_response :forbidden
    end

    test "administrator creates leave type" do
      sign_in_as(@administrator)

      assert_difference("LeaveType.count", 1) do
        post admin_leave_types_path, params: {
          leave_type: { name: "Study leave", code: "study", active: true,
            holiday_handling: "exclude_public_holidays" }
        }
      end

      assert_redirected_to admin_leave_types_path
      assert_equal "STUDY", LeaveType.order(:id).last.code
      assert_predicate LeaveType.order(:id).last, :exclude_public_holidays?
    end

    test "administrator disables leave type without deleting it" do
      sign_in_as(@administrator)

      assert_no_difference("LeaveType.count") do
        patch admin_leave_type_path(@leave_type), params: {
          leave_type: { name: @leave_type.name, code: @leave_type.code, active: false }
        }
      end

      assert_redirected_to admin_leave_types_path
      assert_not @leave_type.reload.active?
    end

    test "shows required field errors in Russian" do
      sign_in_as(@administrator)

      post admin_leave_types_path, params: {
        leave_type: { name: "", code: "", active: true }
      }

      assert_response :unprocessable_entity
      assert_select ".error-summary", text: /Название не может быть пустым/
      assert_select ".error-summary", text: /Код не может быть пустым/
      assert_select ".error-summary", text: /can't be blank/, count: 0
    end

    private

    def create_user(email_address, role: :employee)
      User.create!(name: "Example User", email_address:, password: "test-password", role:)
    end
  end
end
