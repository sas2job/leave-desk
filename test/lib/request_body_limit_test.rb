require "test_helper"

class RequestBodyLimitTest < ActiveSupport::TestCase
  test "advertised content length is rejected without reading the body" do
    body = StringIO.new("small")
    middleware = RequestBodyLimit.new(->(_env) { flunk("application must not be called") })

    status, = middleware.call(
      "CONTENT_LENGTH" => (RequestBodyLimit::MAX_BYTES + 1).to_s,
      "rack.input" => body
    )

    assert_equal 413, status
    assert_equal 0, body.pos
  end

  test "unknown content length cannot bypass the byte limit" do
    called = false
    middleware = RequestBodyLimit.new(->(_env) { called = true; [ 200, {}, [] ] })
    body = StringIO.new("🌿" * ((RequestBodyLimit::MAX_BYTES / 4) + 1))

    status, = middleware.call("rack.input" => body)

    assert_equal 413, status
    assert_not called
  end

  test "accepted body is restored for downstream parameter parsing" do
    payload = "_method=patch&name=Example"
    application = lambda do |env|
      request = Rack::Request.new(env)
      [ 200, {}, [ "#{env.fetch("REQUEST_METHOD")}:#{request.POST.fetch("name")}" ] ]
    end
    stack = RequestBodyLimit.new(Rack::MethodOverride.new(application))
    env = Rack::MockRequest.env_for("/", method: "POST", input: payload,
      "CONTENT_TYPE" => "application/x-www-form-urlencoded")

    status, _, response = stack.call(env)

    assert_equal 200, status
    assert_equal "PATCH:Example", response.join
  end
end
