require "test_helper"

module Admin
  class UsersControllerTest < ActionDispatch::IntegrationTest
    setup do
      @administrator = create_user("admin@example.test", role: :administrator)
      @employee = create_user("employee@example.test")
      @manager = create_user("manager@example.test", role: :manager)
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

    private

    def create_user(email_address, role: :employee)
      User.create!(name: "Example User", email_address:, password: "test-password", role:)
    end
  end
end
