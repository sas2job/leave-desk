require "test_helper"

module Admin
  class RegionalCalendarsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @administrator = User.create!(name: "Administrator", email_address: "regional-admin@example.test",
        password: "test-password", role: :administrator)
      @employee = User.create!(name: "Employee", email_address: "regional-employee@example.test",
        password: "test-password")
    end

    test "administrator enters a region and its annual calendar" do
      sign_in_as(@administrator)

      assert_difference("Region.count", 1) do
        post admin_regions_path, params: { region: { code: "RU-TA", name: "Республика Татарстан" } }
      end
      region = Region.last
      assert_redirected_to admin_regions_path

      get admin_regions_path
      assert_response :success
      assert_select "body", text: /Республика Татарстан/

      assert_difference("RegionalCalendar.count", 1) do
        post admin_regional_calendars_path, params: { regional_calendar: {
          region_id: region.id.to_s, year: "2026", legal_basis: "Закон Республики Татарстан",
          public_holidays_input: "2026-08-30\n2026-11-06",
          additional_days_off_input: "2026-11-09", complete: "1"
        } }
      end
      calendar = RegionalCalendar.last
      assert_redirected_to admin_regional_calendars_path
      assert_equal [ Date.new(2026, 8, 30), Date.new(2026, 11, 6) ], calendar.public_holidays
      assert_equal [ Date.new(2026, 11, 9) ], calendar.additional_days_off

      patch admin_regional_calendar_path(calendar), params: { regional_calendar: {
        legal_basis: "Обновлённый НПА", public_holidays_input: "2026-11-06",
        additional_days_off_input: ""
      } }
      assert_redirected_to admin_regional_calendars_path
      assert_equal "Обновлённый НПА", calendar.reload.legal_basis
      assert_empty calendar.additional_days_off
    end

    test "employee cannot enter regional calendar" do
      region = Region.create!(code: "RU-TA", name: "Республика Татарстан")
      sign_in_as(@employee)

      get admin_regional_calendars_path
      assert_response :forbidden
      assert_no_difference("RegionalCalendar.count") do
        post admin_regional_calendars_path, params: { regional_calendar: {
          region_id: region.id.to_s, year: "2026", legal_basis: "НПА",
          public_holidays_input: "2026-11-06", additional_days_off_input: ""
        } }
      end
      assert_response :forbidden
    end

    test "unknown region field is rejected before creation" do
      sign_in_as(@administrator)

      assert_no_difference("Region.count") do
        post admin_regions_path, params: { region: {
          code: "RU-TA", name: "Республика Татарстан", unexpected: "private-canary"
        } }
      end

      assert_response :bad_request
      assert_no_match(/private-canary/, response.body)
    end

    test "unknown calendar field is rejected before creation" do
      region = Region.create!(code: "RU-TA", name: "Республика Татарстан")
      sign_in_as(@administrator)

      assert_no_difference("RegionalCalendar.count") do
        post admin_regional_calendars_path, params: { regional_calendar: {
          region_id: region.id.to_s, year: "2026", legal_basis: "НПА",
          public_holidays_input: "2026-11-06", additional_days_off_input: "",
          complete: "1", unexpected: "private-canary"
        } }
      end

      assert_response :bad_request
      assert_no_match(/private-canary/, response.body)
    end

    test "invalid dates do not replace an existing calendar" do
      region = Region.create!(code: "RU-TA", name: "Республика Татарстан")
      calendar = RegionalCalendar.create!(region:, year: 2026, legal_basis: "НПА", complete: true,
        public_holidays: [ Date.new(2026, 11, 6) ])
      sign_in_as(@administrator)

      patch admin_regional_calendar_path(calendar), params: { regional_calendar: {
        legal_basis: "Новый НПА", public_holidays_input: "2026-02-30",
        additional_days_off_input: ""
      } }

      assert_response :unprocessable_entity
      assert_equal "НПА", calendar.reload.legal_basis
      assert_equal [ Date.new(2026, 11, 6) ], calendar.public_holidays
    end
  end
end
