require "test_helper"

class LoginRateLimiterTest < ActiveSupport::TestCase
  setup { @cache = ActiveSupport::Cache::MemoryStore.new }

  test "account failures from different IPs share one limit" do
    LoginRateLimiter::ACCOUNT_LIMIT.times do |index|
      limiter("192.0.2.#{index}", " Employee@Example.Test ").record_failure!
    end

    assert limiter("198.51.100.1", "employee@example.test").blocked?
    assert_not limiter("198.51.100.1", "other@example.test").blocked?
  end

  test "failures across accounts share an IP limit" do
    LoginRateLimiter::IP_LIMIT.times do |index|
      limiter("192.0.2.1", "employee#{index}@example.test").record_failure!
    end

    assert limiter("192.0.2.1", "new@example.test").blocked?
    assert_not limiter("192.0.2.2", "new@example.test").blocked?
  end

  test "failure counters expire" do
    LoginRateLimiter::ACCOUNT_LIMIT.times { limiter("192.0.2.1", "employee@example.test").record_failure! }
    assert limiter("192.0.2.1", "employee@example.test").blocked?

    travel 3.minutes + 1.second

    assert_not limiter("192.0.2.1", "employee@example.test").blocked?
  end

  test "cache keys do not contain IP addresses or email addresses" do
    limiter("192.0.2.1", "employee@example.test").record_failure!

    @cache.instance_variable_get(:@data).each_key do |key|
      assert_not_includes key, "192.0.2.1"
      assert_not_includes key, "employee@example.test"
    end
  end

  private

  def limiter(ip_address, email_address)
    LoginRateLimiter.new(ip_address:, email_address:, cache: @cache)
  end
end
