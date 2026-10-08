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
