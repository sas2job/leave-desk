require "test_helper"
require "puma"
require "puma/configuration"
require "yaml"

class RequestBodyLimitsConfigurationTest < ActiveSupport::TestCase
  LIMIT = RequestBodyLimit::MAX_BYTES

  test "Rack rejects bodies before method override parses forms" do
    middleware = Rails.application.middleware.map(&:klass)

    assert_operator middleware.index(RequestBodyLimit), :<, middleware.index(Rack::MethodOverride)
  end

  test "Puma enforces the shared byte limit while receiving requests" do
    configuration = Puma::Configuration.new(
      { config_files: [ Rails.root.join("config/puma.rb").to_s ] }
    )
    configuration.load
    configuration.clamp

    assert_equal LIMIT, configuration.options[:http_content_length_limit]
  end

  test "Thruster and Caddy enforce the shared byte limit" do
    compose = YAML.safe_load_file(Rails.root.join("deploy/compose.yml"), aliases: true)
    environment = compose.dig("services", "web", "environment")
    caddyfile = Rails.root.join("deploy/Caddyfile").read

    assert_equal LIMIT.to_s, environment.fetch("THRUSTER_MAX_REQUEST_BODY")
    assert_match(/request_body\s*\{\s*max_size #{LIMIT}\s*\}/m, caddyfile)
  end
end
