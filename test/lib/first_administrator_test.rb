require "test_helper"
require Rails.root.join("lib/first_administrator")

class FirstAdministratorTest < ActiveSupport::TestCase
  test "creates first administrator and rerun preserves it" do
    credentials = { name: "Initial Admin", email_address: "admin@example.test",
                    password: "first-password" }

    assert_difference("User.count", 1) do
      assert_equal :created, FirstAdministrator.create!(**credentials)
    end
    administrator = User.find_by!(email_address: credentials.fetch(:email_address))
    assert administrator.administrator?
    assert administrator.active?

    assert_no_difference("User.count") do
      assert_equal :already_exists, FirstAdministrator.create!(
        name: "Replacement", email_address: "replacement@example.test",
        password: "second-password"
      )
    end
    assert_equal "Initial Admin", administrator.reload.name
    assert administrator.authenticate("first-password")
    assert_not administrator.authenticate("second-password")
  end

  test "refuses to bootstrap over existing non-administrator users" do
    User.create!(name: "Employee", email_address: "employee@example.test",
                 password: "test-password")

    assert_no_difference("User.count") do
      assert_raises(FirstAdministrator::ExistingUsers) do
        FirstAdministrator.create!(name: "Admin", email_address: "admin@example.test",
                                   password: "test-password")
      end
    end
  end
end
