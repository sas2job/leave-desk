module LeaveRecallTestHelper
  def prepare_recall_scenario
    @manager = User.create!(name: "Recall Manager", email_address: "recall-manager@example.test",
      password: "test-password", role: :manager)
    @employee = User.create!(name: "Recall Employee", email_address: "recall-employee@example.test",
      password: "test-password", manager: @manager, birthday_on: Date.new(1990, 1, 1))
    @annual = LeaveType.find_or_create_by!(code: "ANNUAL") do |type|
      type.name = "Ежегодный отпуск"
      type.holiday_handling = :exclude_public_holidays
    end
    FederalCalendar.find_or_create_by!(year: 2026) do |calendar|
      calendar.legal_basis = "Тестовый календарь"
      calendar.public_holidays = RussianFederalHoliday.fixed_dates_for(2026)
    end
    travel_to Time.zone.local(2026, 10, 1, 12) do
      @leave_request = LeaveRequest.create!(employee: @employee, leave_type: @annual,
        starts_on: Date.new(2026, 10, 1), ends_on: Date.new(2026, 10, 20),
        start_time: "00:00", end_time: "24:00")
      @leave_request.approve!(by: @manager)
    end
  end

  def propose_recall(**attributes)
    LeaveRecall.propose!(leave_request: @leave_request, by: @manager,
      return_on: Date.new(2026, 10, 16), reason: "Срочная задача команды",
      eligibility_confirmed: true, **attributes)
  end

  def consent_to_recall(recall)
    recall.consent!(by: @employee, remainder_option: :choose_dates,
      remainder_preference: "Предоставить оставшуюся часть в удобное мне время")
  end

  def confirm_recall(recall, **attributes)
    recall.confirm!(by: @manager, order_number: "TEST-12", order_on: Date.new(2026, 10, 14),
      consent_reference: "Согласие работника от 14.10.2026", eligibility_confirmed: true, **attributes)
  end
end
