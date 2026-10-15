class LoginRateLimiter
  WINDOW = 3.minutes
  ACCOUNT_LIMIT = 10
  IP_LIMIT = 100

  def initialize(ip_address:, email_address:, cache: Rails.cache)
    @cache = cache
    @ip_key = digest_key("ip", ip_address.to_s)
    normalized_email = email_address&.strip&.downcase
    @account_key = digest_key("account", normalized_email) if normalized_email.present?
  end

  def blocked?
    count(@ip_key) >= IP_LIMIT || (@account_key.present? && count(@account_key) >= ACCOUNT_LIMIT)
  end

  def record_failure!
    @cache.increment(@ip_key, 1, expires_in: WINDOW, initial: 0)
    @cache.increment(@account_key, 1, expires_in: WINDOW, initial: 0) if @account_key
  end

  private

  def count(key)
    @cache.read(key).to_i
  end

  def digest_key(kind, value)
    digest = OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "#{kind}:#{value}")
    "failed_logins:#{kind}:#{digest}"
  end
end
