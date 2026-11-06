class LeaveLegalReview < ApplicationRecord
  belongs_to :leave_request
  belongs_to :reviewer, class_name: "User"
  validates :conditions_confirmed, acceptance: { accept: true }
  validates :confirmed_at, presence: true
  validates :document_reference, length: { maximum: 200 }
  validates :document_reference, presence: true, unless: :annual?
  validates :working_year_starts_on, :working_year_ends_on, :entitlement_days, presence: true, if: :annual?
  validates :entitlement_days, numericality: { only_integer: true, greater_than_or_equal_to: 28 }, if: :annual?
  validate :annual_basis_is_valid, if: :annual?
  validate :maternity_document_covers_request
  validate :leap_day_age_boundary_is_confirmed
  before_update :retain_history
  before_destroy :retain_history

  private

  def leap_day_age_boundary_is_confirmed
    date = leave_request.child_born_on
    if leave_request.childcare_leave? && date&.month == 2 && date.day == 29 && !age_boundary_confirmed?
      errors.add(:age_boundary_confirmed, "для даты рождения 29 февраля требуется отдельная кадровая проверка возрастной границы")
    end
  end

  def annual_basis_is_valid
    first, last = working_year_starts_on, working_year_ends_on
    unless first.is_a?(Date) && last.is_a?(Date) && SupportedCalendarPeriod::DATES.cover?(first) &&
        SupportedCalendarPeriod::DATES.cover?(last) && last >= first
      errors.add(:base, "Укажите проверенные границы рабочего года сотрудника")
    end
    birthday = leave_request.employee.birthday_on
    if birthday.is_a?(Date) && birthday > leave_request.starts_on.prev_year(18) && entitlement_days.to_i < 31
      errors.add(:entitlement_days, "для работника младше 18 лет должно быть не менее 31 дня")
    end
  end

  def maternity_document_covers_request
    return unless leave_request.maternity_leave?

    first, last = document_starts_on, document_ends_on
    unless first.is_a?(Date) && last.is_a?(Date) && SupportedCalendarPeriod::DATES.cover?(first) &&
        SupportedCalendarPeriod::DATES.cover?(last) && first <= leave_request.starts_on && last >= leave_request.ends_on
      errors.add(:base, "Заявленный период должен входить в период документа по беременности и родам")
    end
  end

  def retain_history
    errors.add(:base, "Кадровое основание сохраняется в истории")
    throw :abort
  end
end
