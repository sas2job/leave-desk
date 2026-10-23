require "test_helper"

class ComposeLoggingTest < ActiveSupport::TestCase
  test "every long-lived service has bounded Docker logs" do
    services = YAML.safe_load_file(Rails.root.join("deploy/compose.yml"), aliases: true).fetch("services")
    expected = { "driver" => "json-file", "options" => { "max-size" => "10m", "max-file" => "3" } }

    %w[caddy db web].each do |service|
      assert_equal expected, services.fetch(service).fetch("logging"), "#{service} logging"
    end
  end
end
