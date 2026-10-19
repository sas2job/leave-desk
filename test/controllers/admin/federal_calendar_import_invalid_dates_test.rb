require "test_helper"

module Admin
  class FederalCalendarImportInvalidDatesTest < ActionDispatch::IntegrationTest
    INVALID_DATES = [ "infinity", "-infinity", "2026-02-30", "2026-1-01" ].freeze

    setup do
      administrator = User.create!(name: "Administrator", email_address: "invalid-date-admin@example.test",
        password: "test-password", role: :administrator)
      sign_in_as(administrator)
    end

    test "upload reports every invalid raw holiday without side effects" do
      INVALID_DATES.each do |value|
        Tempfile.create([ "federal-calendar", ".json" ]) do |file|
          file.write(calendar_json(value))
          file.flush

          assert_no_difference([ "FederalCalendar.count", "LeaveRequestEvent.count", "Notification.count" ]) do
            post import_admin_federal_calendars_path, params: {
              calendar_file: Rack::Test::UploadedFile.new(file.path, "application/json")
            }
          end
        end

        assert_response :unprocessable_entity
        assert_select ".error-summary", text: /Праздничные даты должны быть в формате ГГГГ-ММ-ДД/
      end
    end

    private

    def calendar_json(value)
      { year: 2026, legal_basis: "НПА", public_holidays: [ value ], transfers: [] }.to_json
    end
  end
end
