require "test_helper"

class UnusedActiveStorageRoutesTest < ActionDispatch::IntegrationTest
  test "storage routes are unavailable anonymously and after sign in" do
    routes = Rails.application.routes
    {
      post: "/rails/active_storage/direct_uploads",
      put: "/rails/active_storage/disk/token",
      get: "/rails/active_storage/blobs/redirect/id/file.txt"
    }.each do |method, path|
      assert_raises(ActionController::RoutingError) { routes.recognize_path(path, method:) }
    end

    post "/rails/active_storage/direct_uploads", params: { blob: { filename: "file.txt" } }, as: :json
    assert_response :not_found

    user = User.create!(name: "Employee", email_address: "employee@example.test", password: "test-password")
    sign_in_as(user)
    post "/rails/active_storage/direct_uploads", params: { blob: { filename: "file.txt" } }, as: :json
    assert_response :not_found
  end

  test "forms and stylesheet remain available" do
    get new_session_path
    assert_response :success
    stylesheet = css_select("link[rel='stylesheet']").first
    assert stylesheet

    get stylesheet["href"]
    assert_response :success

    administrator = User.create!(name: "Administrator", email_address: "admin@example.test",
      password: "test-password", role: :administrator)
    sign_in_as(administrator)
    get admin_federal_calendars_path
    assert_response :success
    assert_select "input[type='file'][name='calendar_file']"
  end
end
