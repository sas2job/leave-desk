require "test_helper"

class RequestBodyLimitTest < ActiveSupport::TestCase
  test "unknown content length cannot bypass the byte limit" do
    called = false
    middleware = RequestBodyLimit.new(->(_env) { called = true; [ 200, {}, [] ] })
    body = StringIO.new("🌿" * ((RequestBodyLimit::MAX_BYTES / 4) + 1))

    status, = middleware.call("rack.input" => body)

    assert_equal 413, status
    assert_not called
  end
end
