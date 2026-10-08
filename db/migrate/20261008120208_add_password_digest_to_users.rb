class AddPasswordDigestToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :password_digest, :string

    require "bcrypt"
    require "securerandom"

    select_values("SELECT id FROM users WHERE password_digest IS NULL").each do |id|
      digest = BCrypt::Password.create(SecureRandom.base64(48))
      execute <<~SQL.squish
        UPDATE users
        SET password_digest = #{connection.quote(digest)}
        WHERE id = #{connection.quote(id)}
      SQL
    end

    change_column_null :users, :password_digest, false
  end

  def down
    remove_column :users, :password_digest
  end
end
