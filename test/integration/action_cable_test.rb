require "test_helper"

class ActionCableTest < ActionDispatch::IntegrationTest
  test "unused cable endpoint is not mounted" do
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/cable", method: :get)
    end
  end
end
