module SystemTestClockHelper
  class Middleware
    def initialize(app)
      @app = app
    end

    def call(env)
      status, headers, body = @app.call(env)
      # Chrome uses HTTP Date to account for clock skew when expiring cookies.
      # Puma's wall clock would make cookies from our frozen test clock expire.
      [ status, headers.merge("date" => Time.current.httpdate), body ]
    end
  end
end

ActiveSupport.on_load(:action_dispatch_system_test_case) do
  setup do
    unless Capybara.app.is_a?(SystemTestClockHelper::Middleware)
      Capybara.app = SystemTestClockHelper::Middleware.new(Capybara.app)
    end
  end
end
