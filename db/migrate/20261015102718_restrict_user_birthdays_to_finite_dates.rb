class RestrictUserBirthdaysToFiniteDates < ActiveRecord::Migration[8.1]
  def up
    add_check_constraint :users, "birthday_on IS NULL OR isfinite(birthday_on)",
      name: "users_finite_birthday", validate: false

    # Existing invalid values can be repaired through the administration form.
    # Do not block deployment or silently replace an existing birthday.
    return if select_value("SELECT EXISTS (SELECT 1 FROM users WHERE birthday_on IS NOT NULL AND NOT isfinite(birthday_on))")

    validate_check_constraint :users, name: "users_finite_birthday"
  end

  def down
    remove_check_constraint :users, name: "users_finite_birthday"
  end
end
