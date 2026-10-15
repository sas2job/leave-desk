module FirstAdministrator
  class ExistingUsers < StandardError; end

  def self.create!(name:, email_address:, password:)
    User.transaction do
      User.connection.execute("SELECT pg_advisory_xact_lock(20261015, 1)")

      if User.administrator.exists?
        :already_exists
      elsif User.exists?
        raise ExistingUsers
      else
        User.create!(name:, email_address:, password:, role: :administrator)
        :created
      end
    end
  end
end
