class AddUserIntegrityConstraints < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :users, "role IN (0, 1, 2)", name: "users_valid_role"
    add_check_constraint :users, "manager_id IS NULL OR manager_id <> id",
      name: "users_manager_is_not_self"
  end
end
