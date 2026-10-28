require "test_helper"

class UserBirthdayConstraintTest < ActiveSupport::TestCase
  test "database rejects non-finite birthdays on update" do
    user = User.create!(name: "Example Employee", email_address: "employee@example.test",
      password: "test-password", birthday_on: Date.new(1980, 5, 4))

    [ "infinity", "-infinity" ].each do |invalid_date|
      error = assert_raises(ActiveRecord::CheckViolation) do
        User.transaction(requires_new: true) do
          User.where(id: user.id).update_all(birthday_on: Arel.sql("'#{invalid_date}'::date"))
        end
      end
      assert_equal "users_finite_birthday",
        error.cause.result.error_field(PG::Result::PG_DIAG_CONSTRAINT_NAME)
      assert_equal Date.new(1980, 5, 4), user.reload.birthday_on
    end
  end
end
