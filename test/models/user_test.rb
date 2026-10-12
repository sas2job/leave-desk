require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "normalizes email address" do
    user = User.create!(name: "Example Employee", email_address: "  Employee@Example.Test ",
      password: "test-password")

    assert_equal "employee@example.test", user.email_address
  end

  test "email address is case-insensitively unique" do
    User.create!(name: "First Employee", email_address: "employee@example.test",
      password: "test-password")
    duplicate = User.new(name: "Second Employee", email_address: "EMPLOYEE@example.test",
      password: "test-password")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:email_address], "уже используется"
  end

  test "manager must be active and have manager role" do
    employee = User.create!(name: "Employee", email_address: "employee@example.test",
      password: "test-password")
    inactive_manager = User.create!(name: "Manager", email_address: "manager@example.test",
      password: "test-password", role: :manager, active: false)

    employee.manager = inactive_manager

    assert_not employee.valid?
    assert_includes employee.errors[:manager], "должен быть активным руководителем"
  end

  test "manager with direct reports cannot be demoted" do
    manager = User.create!(name: "Manager", email_address: "manager@example.test",
      password: "test-password", role: :manager)
    User.create!(name: "Employee", email_address: "employee@example.test",
      password: "test-password", manager:)

    manager.role = :employee

    assert_not manager.valid?
    assert_includes manager.errors[:role], "нельзя изменить, пока у пользователя есть подчинённые"
  end

  test "unrelated user changes preserve sessions" do
    user = User.create!(name: "Employee", email_address: "employee@example.test",
      password: "test-password")
    session = user.sessions.create!

    user.update!(name: "Updated Employee")

    assert Session.exists?(session.id)
  end

  test "password replacement revokes every session for the user" do
    user = User.create!(name: "Employee", email_address: "employee@example.test",
      password: "test-password")
    2.times { user.sessions.create! }

    user.update!(password: "replacement-password")

    assert_empty user.sessions.reload
  end
end
