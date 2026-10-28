require "stringio"

class RequestBodyLimit
  MAX_BYTES = 1_048_576

  def initialize(app)
    @app = app
  end

  def call(env)
    input = env["rack.input"]
    return @app.call(env) unless input
    return too_large if env["CONTENT_LENGTH"].to_i > MAX_BYTES

    body = input.read(MAX_BYTES + 1).to_s
    return too_large if body.bytesize > MAX_BYTES

    env["rack.input"] = StringIO.new(body)
    @app.call(env)
  end

  private

  def too_large
    body = "Payload Too Large"
    [ 413, { "content-type" => "text/plain; charset=utf-8", "content-length" => body.bytesize.to_s }, [ body ] ]
  end
end
