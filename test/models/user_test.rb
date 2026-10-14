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

  test "requires a new password of at least twelve characters" do
    user = User.new(name: "Employee", email_address: "employee@example.test", password: "1")

    assert_not user.valid?
    assert_includes user.errors[:password], "длина меньше 12 символов"

    user.password = "a" * 12
    assert user.valid?
    user.save!

    user.password = "short"
    assert_not user.valid?
    assert user.reload.authenticate("a" * 12)
  end

  test "password limit accepts Unicode within bcrypt byte limit" do
    user = User.new(name: "Employee", email_address: "employee@example.test",
      password: "😀" * 18)

    assert user.valid?
    user.password = "😀" * 19
    assert_not user.valid?
    assert_predicate user.errors[:password], :present?
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

  test "rejects invalid activity, birthday and manager identifiers" do
    user = User.new(name: "Employee", email_address: "employee@example.test",
      password: "test-password", active: "inactive", birthday_on: "not-a-date",
      manager_id: "123abc")

    assert_not user.valid?
    assert_includes user.errors[:active], "должна быть указана как да или нет"
    assert_includes user.errors[:birthday_on], "содержит неверную дату"
    assert_includes user.errors[:manager], "должен быть выбран из списка"
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
