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

    assert_response :unprocessable_entity
    assert_select "input[name='email_address'][value='employee@example.test']"
  end

  test "rejects inactive user" do
    @user.update!(active: false)

    assert_no_difference("Session.count") do
      post session_path, params: {
        email_address: @user.email_address, password: "test-password"
      }
    end

    assert_response :unprocessable_entity
  end

  test "malformed login fields do not raise or create a session" do
    [ { email_address: [ @user.email_address ], password: "test-password" },
      { email_address: @user.email_address, password: { nested: "test-password" } },
      { password: "test-password" } ].each do |credentials|
      assert_no_difference("Session.count") do
        post session_path, params: credentials
      end
      assert_response :unprocessable_entity
      assert_select ".flash--alert", text: /Неверный адрес электронной почты или пароль/
    end
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

  test "returns to a requested page with a bounded query after sign in" do
    destination = calendar_path(year: 2026, month: 10, q: "a" * 800)

    get destination
    assert_redirected_to new_session_path
    sign_in_as(@user)

    assert_redirected_to destination
  end

  test "long ASCII return destination falls back to home" do
    get root_path, params: { q: "a" * 5_000 }
    assert_redirected_to new_session_path

    sign_in_as(@user)

    assert_redirected_to root_path
  end

  test "long encoded Unicode return destination falls back to home" do
    get root_path, params: { q: "Ж" * 800 }
    assert_redirected_to new_session_path

    sign_in_as(@user)

    assert_redirected_to root_path
  end

  test "expired session cancellation returns to home after sign in" do
    previous_forgery_protection = ActionController::Base.allow_forgery_protection
    leave_type = LeaveType.create!(name: "Отпуск", code: "TEST_ANNUAL")
    leave_request = LeaveRequest.create!(employee: @user, leave_type:,
      starts_on: Date.new(2026, 10, 20), ends_on: Date.new(2026, 10, 20))
    sign_in_as(@user)
    ActionController::Base.allow_forgery_protection = true

    get leave_requests_path
    cancellation_token = css_select("form[action='#{leave_request_path(leave_request)}'] " \
      "input[name='authenticity_token']").first["value"]
    Session.last.update_column(:created_at, 31.days.ago)
    delete leave_request_path(leave_request), params: { authenticity_token: cancellation_token }
    assert_redirected_to new_session_path

    get new_session_path
    login_token = css_select("form[action='#{session_path}'] " \
      "input[name='authenticity_token']").first["value"]
    post session_path, params: { email_address: @user.email_address,
      password: "test-password", authenticity_token: login_token }

    assert_redirected_to root_path
    assert_predicate leave_request.reload, :pending?
  ensure
    ActionController::Base.allow_forgery_protection = previous_forgery_protection
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
