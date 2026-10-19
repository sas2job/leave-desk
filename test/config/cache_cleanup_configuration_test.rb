require "test_helper"

class CacheCleanupConfigurationTest < ActiveSupport::TestCase
  test "systemd service cleans the running web container cache" do
    service = Rails.root.join("deploy/leave-desk-cache-cleanup.service").read

    assert_includes service,
      "ExecStart=/usr/bin/docker compose exec -T web bin/rails runner Rails.cache.cleanup"
  end

  test "systemd timer runs cleanup every fifteen minutes" do
    timer = Rails.root.join("deploy/leave-desk-cache-cleanup.timer").read

    assert_includes timer, "OnCalendar=*:0/15"
    assert_includes timer, "Persistent=true"
  end

  test "deployment copies cache cleanup units" do
    workflow = Rails.root.join(".github/workflows/deploy.yml").read

    assert_includes workflow, "deploy/leave-desk-cache-cleanup.service"
    assert_includes workflow, "deploy/leave-desk-cache-cleanup.timer"
  end
end
