require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: "Example Employee", email_address: "employee@example.test",
      password: "test-password")
  end

  test "shows sign in form without authentication" do
    get new_session_path

    assert_response :success
  end

  test "redirects unauthenticated user to sign in" do
    get root_path

    assert_redirected_to new_session_path
  end

  test "creates session with valid credentials" do
    assert_difference("Session.count", 1) do
      post session_path, params: {
        email_address: " Employee@Example.Test ", password: "test-password"
      }
    end

    assert_redirected_to root_path
  end

  test "rejects invalid credentials" do
    assert_no_difference("Session.count") do
      post session_path, params: {
        email_address: @user.email_address, password: "wrong-password"
      }
    end

    assert_redirected_to new_session_path
  end

  test "rejects inactive user" do
    @user.update!(active: false)

    assert_no_difference("Session.count") do
      post session_path, params: {
        email_address: @user.email_address, password: "test-password"
      }
    end

    assert_redirected_to new_session_path
  end

  test "deactivation revokes an existing session" do
    sign_in_as(@user)

    assert_difference("Session.count", -1) { @user.update!(active: false) }

    get root_path
    assert_redirected_to new_session_path
  end

  test "inactive account is refused even if its session record remains" do
    sign_in_as(@user)
    @user.update_column(:active, false)

    get root_path
    assert_redirected_to new_session_path
  end

  test "password replacement revokes an existing session" do
    sign_in_as(@user)

    assert_difference("Session.count", -1) do
      @user.update!(password: "replacement-password")
    end

    get root_path
    assert_redirected_to new_session_path

    sign_in_as(@user, password: "replacement-password")
    assert_redirected_to root_path
  end

  test "expired server session cannot authenticate" do
    sign_in_as(@user)
    Session.last.update_column(:created_at, 31.days.ago)

    get root_path
    assert_redirected_to new_session_path
  end

  test "stale credentials cannot create a session after password replacement" do
    authenticated_user = User.find(@user.id)
    @user.update!(password: "replacement-password")

    assert_no_difference("Session.count") do
      assert_equal false, SessionsController.new.send(:start_new_session_for, authenticated_user)
    end
  end

  test "stale active state cannot create a session after deactivation" do
    authenticated_user = User.find(@user.id)
    @user.update!(active: false)

    assert_no_difference("Session.count") do
      assert_equal false, SessionsController.new.send(:start_new_session_for, authenticated_user)
    end
  end

  test "destroys current session" do
    post session_path, params: {
      email_address: @user.email_address, password: "test-password"
    }

    assert_difference("Session.count", -1) do
      delete session_path
    end

    assert_redirected_to new_session_path
  end
end
