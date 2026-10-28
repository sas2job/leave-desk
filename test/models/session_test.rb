require "test_helper"

class SessionTest < ActiveSupport::TestCase
  test "prunes only sessions older than the lifetime and is repeatable" do
    user = User.create!(name: "Employee", email_address: "employee@example.test",
                        password: "test-password")
    expired = user.sessions.create!(created_at: Session::LIFETIME.ago - 1.second)
    boundary = user.sessions.create!(created_at: Session::LIFETIME.ago)
    current = user.sessions.create!(created_at: Session::LIFETIME.ago + 1.second)

    assert_difference("Session.count", -1) { Session.prune_expired! }
    assert_not Session.exists?(expired.id)
    assert Session.exists?(boundary.id)
    assert Session.exists?(current.id)
    assert_no_difference("Session.count") { Session.prune_expired! }
  end
end
