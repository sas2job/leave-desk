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
    assert_includes duplicate.errors[:email_address], "has already been taken"
  end
end
