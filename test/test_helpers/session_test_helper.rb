module SessionTestHelper
  def sign_in_as(user, password: "test-password")
    post session_path, params: { email_address: user.email_address, password: }
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include SessionTestHelper
end
