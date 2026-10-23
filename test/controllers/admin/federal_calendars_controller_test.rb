require "test_helper"

module Admin
  class FederalCalendarsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @administrator = User.create!(name: "Administrator", email_address: "admin@example.test",
        password: "test-password", role: :administrator)
      @employee = User.create!(name: "Employee", email_address: "employee@example.test",
        password: "test-password")
    end

    test "calendar year form uses supported period" do
      sign_in_as(@administrator)

      get new_admin_federal_calendar_path

      assert_response :success
      assert_select "input[name='federal_calendar[year]'][min='2000'][max='2100']"
    end

    test "only administrators can manage calendars" do
      sign_in_as(@employee)
      get admin_federal_calendars_path
      assert_response :forbidden
      assert_no_difference("FederalCalendar.count") do
        post admin_federal_calendars_path, params: { federal_calendar: calendar_attributes }
      end
      assert_response :forbidden
    end

    test "administrator creates and updates calendar with legal basis" do
      sign_in_as(@administrator)
      assert_difference("FederalCalendar.count", 1) do
        post admin_federal_calendars_path, params: { federal_calendar: calendar_attributes }
      end
      calendar = FederalCalendar.last
      assert_redirected_to admin_federal_calendars_path
      assert_equal [ Date.new(2026, 1, 1) ], calendar.public_holidays
      assert_equal [ { "from" => "2026-03-07", "to" => "2026-03-09" } ], calendar.transfers

      patch admin_federal_calendar_path(calendar), params: { federal_calendar: {
        legal_basis: "Новое постановление", public_holidays_input: "2026-01-01\n2026-06-12",
        transfers_input: ""
      } }
      assert_redirected_to admin_federal_calendars_path
      assert_equal "Новое постановление", calendar.reload.legal_basis
      assert_equal 2, calendar.public_holidays.size
      assert_empty calendar.transfers
    end

    test "large duplicate form collections are rejected without creating a calendar" do
      sign_in_as(@administrator)
      attributes = calendar_attributes.merge(
        public_holidays_input: "2026-01-01\n" * 10_000,
        transfers_input: "2026-02-01 -> 2026-02-02\n" * 10_000
      )

      assert_no_difference("FederalCalendar.count") do
        post admin_federal_calendars_path, params: { federal_calendar: attributes }
      end
      assert_response :unprocessable_entity
      assert_select ".error-summary", text: /366 строк/
    end

    test "invalid dates leave published calendar unchanged" do
      calendar = FederalCalendar.create!(year: 2026, legal_basis: "НПА",
        public_holidays: [ Date.new(2026, 1, 1) ])
      sign_in_as(@administrator)
      patch admin_federal_calendar_path(calendar), params: { federal_calendar: {
        legal_basis: "Исправленный НПА", public_holidays_input: "2027-01-01",
        transfers_input: ""
      } }
      assert_response :unprocessable_entity
      assert_equal "НПА", calendar.reload.legal_basis
      assert_equal [ Date.new(2026, 1, 1) ], calendar.public_holidays
    end

    test "rejects typed JSON fields and malformed year" do
      sign_in_as(@administrator)
      assert_no_difference("FederalCalendar.count") do
        post admin_federal_calendars_path, params: {
          federal_calendar: calendar_attributes.merge(legal_basis: 123)
        }, as: :json
      end
      assert_response :bad_request

      assert_no_difference("FederalCalendar.count") do
        post admin_federal_calendars_path, params: {
          federal_calendar: calendar_attributes.merge(year: "2026x")
        }
      end
      assert_response :unprocessable_entity
    end

    test "administrator imports file selected from computer" do
      sign_in_as(@administrator)
      Tempfile.create([ "federal-calendar", ".json" ]) do |file|
        file.write({ year: 2026, legal_basis: "НПА", public_holidays: [ "2026-01-01" ],
          transfers: [] }.to_json)
        file.flush
        assert_difference("FederalCalendar.count", 1) do
          post import_admin_federal_calendars_path, params: {
            calendar_file: Rack::Test::UploadedFile.new(file.path, "application/json")
          }
        end
      end
      assert_redirected_to admin_federal_calendars_path
      assert_equal "НПА", FederalCalendar.last.legal_basis
    end

    test "employee cannot import a calendar" do
      sign_in_as(@employee)
      post import_admin_federal_calendars_path
      assert_response :forbidden
    end

    test "invalid calendar years show complete Russian numericality errors" do
      sign_in_as(@administrator)
      expected_errors = {
        "" => "Год: значение должно быть числом",
        "year" => "Год: значение должно быть числом",
        "2026.5" => "Год: значение должно быть целым числом",
        "1999" => "Год: значение должно входить в диапазон 2000..2100"
      }

      expected_errors.each do |year, message|
        assert_no_difference("FederalCalendar.count") do
          post admin_federal_calendars_path, params: {
            federal_calendar: calendar_attributes.merge(year:)
          }
        end

        assert_response :unprocessable_entity
        assert_select ".error-summary li", text: message
        assert_no_match(/Translation missing/i, response.body)
      end
    end

    private

    def calendar_attributes
      { year: "2026", legal_basis: "Статья 112 ТК РФ; постановление о переносах",
        public_holidays_input: "2026-01-01", transfers_input: "2026-03-07 -> 2026-03-09" }
    end
  end
end
