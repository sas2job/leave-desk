require "test_helper"

module Admin
  class LeaveTypesControllerTest < ActionDispatch::IntegrationTest
  test "rejects malformed activation flag without changing leave type" do
    sign_in_as(@administrator)

    patch admin_leave_type_path(@leave_type), params: { leave_type: {
      name: "Changed", code: @leave_type.code, active: "disabled"
    } }

    assert_response :unprocessable_entity
    assert_equal "Annual leave", @leave_type.reload.name
    assert_predicate @leave_type, :active?
  end

    setup do
      @administrator = create_user("admin@example.test", role: :administrator)
      @employee = create_user("employee@example.test")
      @leave_type = LeaveType.create!(name: "Annual leave", code: "TEST_ANNUAL")
    end

    test "rejects numeric JSON leave type fields without creating a type" do
      sign_in_as(@administrator)
      attributes = { name: "Study leave", code: "TEST_STUDY",
        holiday_handling: "include_public_holidays", active: true }

      %i[name code holiday_handling].each do |field|
        assert_no_difference("LeaveType.count") do
          post admin_leave_types_path, params: { leave_type: attributes.merge(field => 123) }, as: :json
        end
        assert_response :bad_request
      end
    end

    test "rejects numeric JSON leave type update without changing data" do
      sign_in_as(@administrator)

      patch admin_leave_type_path(@leave_type), params: { leave_type: { code: 123 } }, as: :json

      assert_response :bad_request
      assert_equal "TEST_ANNUAL", @leave_type.reload.code
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
          leave_type: { name: "Study leave", code: "test_study", active: true,
            holiday_handling: "exclude_public_holidays" }
        }
      end

      assert_redirected_to admin_leave_types_path
      assert_equal "TEST_STUDY", LeaveType.order(:id).last.code
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

    test "cannot change holiday policy after the first request" do
      LeaveRequest.create!(employee: @employee, leave_type: @leave_type,
        starts_on: Date.new(2026, 12, 1), ends_on: Date.new(2026, 12, 2))
      sign_in_as(@administrator)

      patch admin_leave_type_path(@leave_type), params: { leave_type: {
        name: @leave_type.name, code: @leave_type.code,
        holiday_handling: "exclude_public_holidays", active: true
      } }

      assert_response :unprocessable_entity
      assert_predicate @leave_type.reload, :include_public_holidays?
      assert_select ".error-summary", text: /нельзя изменить для вида с существующими заявками/
    end

    test "shows required field errors in Russian" do
      sign_in_as(@administrator)

      post admin_leave_types_path, params: {
        leave_type: { name: "", code: "", active: true }
      }

      assert_response :unprocessable_entity
      assert_select ".error-summary li", text: "Название: обязательное поле"
      assert_select ".error-summary li", text: "Код: обязательное поле"
      assert_select ".error-summary", text: /can't be blank/, count: 0
    end

    test "shows invalid options with Russian field names" do
      sign_in_as(@administrator)

      post admin_leave_types_path, params: { leave_type: {
        name: "Study leave", code: "STUDY", holiday_handling: "unknown", active: "unknown"
      } }

      assert_response :unprocessable_entity
      assert_select ".error-summary li", text: "Учёт праздничных дней: недопустимое значение"
      assert_select ".error-summary li", text: "Активность: должна быть указана как да или нет"
    end

    private

    def create_user(email_address, role: :employee)
      User.create!(name: "Example User", email_address:, password: "test-password", role:)
    end
  end
end
