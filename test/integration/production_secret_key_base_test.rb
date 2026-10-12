require "test_helper"
require "open3"

class ProductionSecretKeyBaseTest < ActiveSupport::TestCase
  test "production boot rejects a missing signing key" do
    _stdout, stderr, status = boot_with(nil)

    assert_not status.success?
    assert_includes stderr, "Production SECRET_KEY_BASE must be a unique secret"
  end

  test "production boot rejects the former example signing key" do
    _stdout, stderr, status = boot_with("generate-with-bin-rails-secret")

    assert_not status.success?
    assert_includes stderr, "Production SECRET_KEY_BASE must be a unique secret"
  end

  test "production boot accepts a generated signing key" do
    stdout, stderr, status = boot_with(SecureRandom.hex(64))

    assert status.success?, stderr
    assert_equal "booted", stdout.lines.last.strip
  end

  private

  def boot_with(secret)
    Open3.capture3(
      { "RAILS_ENV" => "production", "SECRET_KEY_BASE" => secret,
        "SECRET_KEY_BASE_DUMMY" => nil },
      Rails.root.join("bin/rails").to_s, "runner", "puts :booted",
      chdir: Rails.root.to_s
    )
  end
end
