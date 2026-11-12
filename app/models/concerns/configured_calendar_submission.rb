module ConfiguredCalendarSubmission
  extend ActiveSupport::Concern

  included do
    validate :submission_calendar_years_are_ready, on: :create, if: :employee_submission?
  end

  def submit
    @employee_submission = true
    save
  rescue ActiveRecord::RecordInvalid => error
    raise unless error.record == self
    false
  end

  private

  def employee_submission?
    @employee_submission == true
  end

  def submission_calendar_years_are_ready
    return if sick_leave?
    years = calendar_years
    return if years.empty?

    missing = years - FederalCalendar.where(year: years).pluck(:year)
    if region_id
      missing |= years - RegionalCalendar.where(region_id:, year: years, complete: true).pluck(:year)
    end
    if missing.any?
      errors.add(:base, "Нельзя отправить заявку: календарь #{missing.sort.join(', ')} года ещё не размечен или не подтверждён")
    end
  end
end
