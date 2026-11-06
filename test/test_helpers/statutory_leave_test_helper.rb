module StatutoryLeaveTestHelper
  def prepare_statutory_scenario
    @manager = User.create!(name: "Law Manager", email_address: "law-manager@example.test", password: "test-password", role: :manager)
    @administrator = User.create!(name: "Law Administrator", email_address: "law-admin@example.test", password: "test-password", role: :administrator)
    @employee = User.create!(name: "Law Employee", email_address: "law-employee@example.test", password: "test-password", manager: @manager)
    @annual = LeaveType.find_or_create_by!(code: "ANNUAL") do |type|
      type.name = "Ежегодный отпуск"
      type.holiday_handling = :exclude_public_holidays
    end
    @birthday = LeaveType.find_or_create_by!(code: "BIRTHDAY") { |type| type.name = "Выходной в день рождения" }
    @maternity = LeaveType.find_or_create_by!(code: "MATERNITY") { |type| type.name = "Отпуск по беременности и родам" }
    @childcare = LeaveType.find_or_create_by!(code: "CHILDCARE") { |type| type.name = "Отпуск по уходу за ребёнком" }
    [ 2026, 2027, 2028 ].each do |year|
      FederalCalendar.find_or_create_by!(year:) do |calendar|
        calendar.legal_basis = "Тестовый календарь"
        calendar.public_holidays = RussianFederalHoliday.fixed_dates_for(year)
      end
    end
  end

  def annual_review_attributes
    { conditions_confirmed: true, working_year_starts_on: Date.new(2026, 2, 1),
      working_year_ends_on: Date.new(2027, 1, 31), entitlement_days: 28 }
  end

  def create_childcare(**attributes)
    LeaveRequest.create!(employee: @employee, leave_type: @childcare,
      starts_on: Date.new(2026, 10, 1), ends_on: Date.new(2028, 1, 1),
      child_born_on: Date.new(2025, 1, 1), care_relationship: :father, **attributes)
  end

  def family_review_attributes
    { conditions_confirmed: true, document_reference: "Заявление и подтверждённое кадровое основание" }
  end
end
