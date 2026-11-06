class LeaveRecall < ApplicationRecord
  class NotAuthorized < StandardError; end
  class InvalidTransition < StandardError; end

  enum :status, { proposed: 0, consented: 1, declined: 2, withdrawn: 3, confirmed: 4 }, validate: true
  enum :remainder_option, { choose_dates: 0, next_work_year: 1 }, prefix: :remainder, validate: { allow_nil: true }

  belongs_to :leave_request
  belongs_to :requested_by, class_name: "User"
  belongs_to :confirmed_by, class_name: "User", optional: true
  attr_readonly :leave_request_id, :requested_by_id, :return_on, :reason, :eligibility_confirmed

  validates :reason, presence: true, length: { maximum: LeaveRequest::COMMENT_MAX_LENGTH }
  validates :eligibility_confirmed, acceptance: { accept: true }
  validates :remainder_preference, length: { maximum: LeaveRequest::COMMENT_MAX_LENGTH }
  validates :remainder_option, :responded_at, presence: true, if: -> { consented? || confirmed? }
  validates :remainder_preference, presence: true, if: -> { (consented? || confirmed?) && remainder_choose_dates? }
  validates :confirmed_by, :confirmed_at, :order_number, :order_on, :consent_reference, presence: true, if: :confirmed?
  validates :order_number, length: { maximum: 100 }
  validates :consent_reference, length: { maximum: 200 }
  validates :unused_days, numericality: { only_integer: true, greater_than: 0 }, if: :confirmed?
  validate :return_date_is_supported
  validate :order_date_is_valid, if: :confirmed?
  before_destroy :retain_history

  def self.propose!(leave_request:, by:, **attributes)
    new(attributes.merge(leave_request:, requested_by: by)).tap { |recall| recall.propose!(by:) }
  end

  def propose!(by:)
    with_context_lock do
      require_manager!(by)
      require_recallable!
      if persisted? || leave_request.leave_recalls.where(status: %i[proposed consented]).exists?
        raise InvalidTransition, "По этой заявке уже есть незавершённый отзыв"
      end
      self.requested_by = by
      save!
      record_event!(:recall_proposed, by:, comment: reason)
    end
  end

  def consent!(by:, remainder_option:, remainder_preference: nil)
    with_context_lock do
      require_employee!(by)
      require_status!(:proposed)
      require_recallable!
      update!(status: :consented, responded_at: Time.current, remainder_option:, remainder_preference:)
      record_event!(:recall_consented, by:, comment: remainder_preference)
    end
  end

  def decline!(by:)
    with_context_lock do
      require_employee!(by)
      require_status!(:proposed)
      update!(status: :declined, responded_at: Time.current)
      record_event!(:recall_declined, by:)
    end
  end

  def withdraw!(by:)
    with_context_lock do
      by&.id == leave_request.employee_id ? require_employee!(by) : require_manager!(by)
      raise InvalidTransition, "Завершённый отзыв нельзя отозвать" unless proposed? || consented?

      update!(status: :withdrawn)
      record_event!(:recall_withdrawn, by:)
    end
  end

  def confirm!(by:, order_number:, order_on:, consent_reference:, eligibility_confirmed:)
    with_context_lock do
      require_manager!(by)
      require_status!(:consented)
      require_recallable!
      raise InvalidTransition, "Подтвердите допустимость отзыва по статье 125 ТК РФ" unless eligibility_confirmed == true

      unused = estimated_unused_days
      update!(status: :confirmed, confirmed_by: by, confirmed_at: Time.current,
        order_number:, order_on:, consent_reference:, unused_days: unused)
      leave_request.update!(status: :recalled, recalled_on: return_on)
      record_event!(:recalled, by:, from_status: :approved,
        comment: "Выход #{return_on.strftime('%d.%m.%Y')}; приказ №#{order_number}; " \
          "неиспользованная часть: #{unused} дн.")
    end
  end

  def estimated_unused_days
    return unless return_on.is_a?(Date) && return_on <= leave_request.ends_on

    days = (leave_request.ends_on - return_on).to_i + 1
    if leave_request.leave_type.exclude_public_holidays?
      days -= PublicHoliday.count_between(return_on, leave_request.ends_on, region_id: leave_request.region_id)
    end
    days
  end

  def self.status_label(status)
    { "proposed" => "Ожидает ответа сотрудника", "consented" => "Сотрудник согласился; ожидает приказа",
      "declined" => "Сотрудник отказался", "withdrawn" => "Предложение отозвано",
      "confirmed" => "Отзыв оформлен" }.fetch(status)
  end

  protected

  def with_context_lock
    leave_request.with_lock do
      employee = User.uncached { User.lock.find(leave_request.employee_id) }
      leave_request.association(:employee).target = employee
      lock! if persisted?
      yield
    end
  end

  def require_manager!(actor)
    unless actor&.active? && actor.manager? && actor.id != leave_request.employee_id &&
        leave_request.employee.manager_id == actor.id
      raise NotAuthorized
    end
  end

  def require_recallable!
    raise InvalidTransition, "Отозвать можно только из начавшегося ежегодного отпуска на полные дни с проверенным расчётом" unless leave_request.recallable?
    unless return_on.is_a?(Date) && return_on > leave_request.employee_today &&
        return_on > leave_request.starts_on && return_on <= leave_request.ends_on
      raise InvalidTransition, "Выход должен быть в будущем и в пределах отпуска"
    end
    birthday = leave_request.employee.birthday_on
    if birthday.is_a?(Date) && birthday > return_on.prev_year(18)
      raise InvalidTransition, "Отзыв работника младше 18 лет запрещён"
    end
    raise InvalidTransition, "В выбранной части нет учитываемых дней отпуска" unless estimated_unused_days.positive?
  end

  def record_event!(type, by:, comment: nil, from_status: leave_request.status)
    leave_request.events.create!(event_type: type, actor: by, comment:, occurred_at: Time.current,
      from_status: LeaveRequest.statuses.fetch(from_status), to_status: LeaveRequest.statuses.fetch(leave_request.status))
  end

  private

  def require_employee!(actor)
    raise NotAuthorized unless actor&.active? && actor.id == leave_request.employee_id
  end

  def require_status!(expected)
    raise InvalidTransition, "Действие недоступно в текущем состоянии отзыва" unless status == expected.to_s
  end

  def return_date_is_supported
    return if return_on.is_a?(Date) && SupportedCalendarPeriod::DATES.cover?(return_on)

    errors.add(:return_on, "укажите допустимую дату")
  end

  def order_date_is_valid
    consent_on = responded_at&.in_time_zone(leave_request.employee.time_zone)&.to_date
    return if order_on.is_a?(Date) && consent_on && order_on >= consent_on &&
      order_on <= leave_request.employee_today && order_on < return_on

    errors.add(:order_on, "должна быть после получения согласия, не позже сегодняшнего дня и раньше выхода")
  end

  def retain_history
    errors.add(:base, "История отзыва сохраняется")
    throw :abort
  end
end
