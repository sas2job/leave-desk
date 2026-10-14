require "test_helper"

module Admin
  class UsersControllerTest < ActionDispatch::IntegrationTest
  test "rejects manager identifier outside database range" do
    sign_in_as(@administrator)

    patch admin_user_path(@employee), params: { user: {
      name: @employee.name, email_address: @employee.email_address,
      role: "employee", manager_id: "9223372036854775808", active: true
    } }

    assert_response :unprocessable_entity
    assert_nil @employee.reload.manager_id
  end

    setup do
      @administrator = create_user("admin@example.test", role: :administrator)
      @employee = create_user("employee@example.test")
      @manager = create_user("manager@example.test", role: :manager)
    end

    test "rejects numeric JSON employee fields without creating a user" do
      sign_in_as(@administrator)
      attributes = { name: "New Employee", email_address: "new@example.test",
        password: "new-password", password_confirmation: "new-password",
        role: "employee", active: true }

      %i[name email_address password password_confirmation role].each do |field|
        assert_no_difference("User.count") do
          post admin_users_path, params: { user: attributes.merge(field => 123) }, as: :json
        end
        assert_response :bad_request
      end
    end

    test "rejects numeric JSON employee update without changing data" do
      sign_in_as(@administrator)

      patch admin_user_path(@employee), params: { user: { email_address: 123 } }, as: :json

      assert_response :bad_request
      assert_equal "employee@example.test", @employee.reload.email_address
    end

    test "rejects malformed manager identifiers without changing data" do
      sign_in_as(@administrator)

      [ true, 1.5, "1.5" ].each do |identifier|
        patch admin_user_path(@employee), params: { user: { manager_id: identifier } }, as: :json

        assert_response :bad_request
        assert_nil @employee.reload.manager_id
      end
    end

    test "non administrator cannot access employee administration" do
      sign_in_as(@employee)

      get admin_users_path

      assert_response :forbidden
    end

    test "administrator creates employee with manager" do
      sign_in_as(@administrator)

      assert_difference("User.count", 1) do
        post admin_users_path, params: { user: {
          name: "New Employee", email_address: " New@Example.Test ",
          password: "new-password", password_confirmation: "new-password",
          role: "employee", manager_id: @manager.id, active: true
        } }
      end

      assert_redirected_to admin_users_path
      user = User.order(:id).last
      assert_equal "new@example.test", user.email_address
      assert_equal @manager, user.manager
    end

    test "administrator updates employee without changing password" do
      sign_in_as(@administrator)

      patch admin_user_path(@employee), params: { user: {
        name: "Updated Employee", email_address: @employee.email_address,
        password: "", password_confirmation: "", role: "employee",
        manager_id: @manager.id, active: true
      } }

      assert_redirected_to admin_users_path
      assert @employee.reload.authenticate("test-password")
      assert_equal @manager, @employee.manager
    end

    test "administrator cannot assign inactive manager" do
      @manager.update!(active: false)
      sign_in_as(@administrator)

      patch admin_user_path(@employee), params: { user: {
        name: @employee.name, email_address: @employee.email_address,
        role: "employee", manager_id: @manager.id, active: true
      } }

      assert_response :unprocessable_entity
      assert_nil @employee.reload.manager
    end

    test "shows validation errors in Russian" do
      sign_in_as(@administrator)

      post admin_users_path, params: { user: {
        name: "Duplicate email", email_address: @employee.email_address,
        password: "new-password", password_confirmation: "new-password",
        role: "employee", active: true
      } }

      assert_response :unprocessable_entity
      assert_select ".error-summary li", text: "Электронная почта: уже используется"
      assert_select ".error-summary", text: /has already been taken/, count: 0
    end

    test "shows invalid employee fields and password confirmation in Russian" do
      sign_in_as(@administrator)

      post admin_users_path, params: { user: {
        name: "Example User", email_address: "new@example.test", birthday_on: "invalid",
        password: "new-password", password_confirmation: "different", role: "unknown", active: true
      } }

      assert_response :unprocessable_entity
      assert_select ".error-summary li", text: "День рождения: содержит неверную дату"
      assert_select ".error-summary li", text: "Роль: недопустимое значение"
      assert_select ".error-summary li", text: "Подтверждение пароля: не совпадает с паролем"
    end

    test "administrator cannot create or replace a password with a short value" do
      sign_in_as(@administrator)

      assert_no_difference("User.count") do
        post admin_users_path, params: { user: {
          name: "New Employee", email_address: "new@example.test", password: "1",
          password_confirmation: "1", role: "employee", active: true
        } }
      end
      assert_response :unprocessable_entity
      assert_select ".error-summary li", text: "Пароль: длина меньше 12 символов"

      patch admin_user_path(@employee), params: { user: { password: "short" } }
      assert_response :unprocessable_entity
      assert @employee.reload.authenticate("test-password")
    end

    test "last active administrator cannot deactivate or demote their account" do
      sign_in_as(@administrator)
      session_record = @administrator.sessions.last

      [ { active: false }, { role: "employee" } ].each do |attributes|
        patch admin_user_path(@administrator), params: { user: attributes }
        assert_response :unprocessable_entity
        assert_select ".error-summary li", text: "Нельзя удалить последнего активного администратора"
        assert @administrator.reload.active?
        assert @administrator.administrator?
        assert Session.exists?(session_record.id)
      end

      get admin_users_path
      assert_response :success
    end

    test "administrator may hand over access before deactivating their account" do
      replacement = create_user("replacement@example.test", role: :administrator)
      sign_in_as(@administrator)

      patch admin_user_path(@administrator), params: { user: { active: false } }

      assert_redirected_to admin_users_path
      assert_not @administrator.reload.active?
      assert replacement.reload.active?
      assert replacement.administrator?
      assert_empty @administrator.sessions.reload
    end

    private

    def create_user(email_address, role: :employee)
      User.create!(name: "Example User", email_address:, password: "test-password", role:)
    end
  end
end
