module FirstAdministrator
  class ExistingUsers < StandardError; end

  SAFE_FIELD_LABELS = {
    name: "Name",
    email_address: "Email",
    password: "Password"
  }.freeze

  def self.validation_failure_message(record)
    diagnostics = record.errors.filter_map do |error|
      label = SAFE_FIELD_LABELS[error.attribute]
      next unless label

      reason = case error.type
      when :blank then "is required"
      when :invalid then "is invalid"
      when :too_short
        error.attribute == :password ? "must have at least #{User::MINIMUM_PASSWORD_LENGTH} characters" : "is too short"
      when :too_long then "is too long"
      else "is invalid"
      end
      "#{label} #{reason}"
    end.uniq

    return "Invalid administrator details; no changes made." if diagnostics.empty?

    "#{diagnostics.join('; ')}; no changes made."
  end

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
