class SickLeaveExtension < ApplicationRecord
  belongs_to :leave_request
  belongs_to :requested_by, class_name: "User"
  belongs_to :reviewer, class_name: "User", optional: true
  enum :status, { pending: 0, approved: 1, rejected: 2, withdrawn: 3 }
  attr_readonly :leave_request_id, :requested_by_id, :previous_ends_on, :proposed_ends_on

  validates :previous_ends_on, :proposed_ends_on, presence: true
  validate :period_is_valid
  before_destroy :retain_history

  def self.propose!(leave_request:, by:, proposed_ends_on:)
    leave_request.with_lock do
      leave_request.lock_sick_employee!
      unless by&.active? && by.id == leave_request.employee_id && leave_request.employee.active?
        raise LeaveRequest::ReviewNotAuthorized
      end
      leave_request.require_open_sick_leave!
      if leave_request.sick_leave_extensions.pending.exists?
        raise LeaveRequest::InvalidTransition, "Продление уже ожидает подтверждения руководителя"
      end
      extension = create!(leave_request:, requested_by: by, proposed_ends_on:, previous_ends_on: leave_request.ends_on)
      extension.record_event!(:sick_extension_proposed, by:)
      extension
    end
  end

  def review!(by:, approve:)
    leave_request.with_lock do
      leave_request.lock_sick_employee!
      reload
      unless by&.active? && by.manager? && by.id != leave_request.employee_id && leave_request.employee.manager_id == by.id
        raise LeaveRequest::ReviewNotAuthorized
      end
      leave_request.require_open_sick_leave!
      unless pending? && previous_ends_on == leave_request.ends_on
        raise LeaveRequest::InvalidTransition, "Это продление уже рассмотрено или период изменился"
      end
      leave_request.change_sick_period!(ends_on: proposed_ends_on) if approve
      update!(status: approve ? :approved : :rejected, reviewer: by, reviewed_at: Time.current)
      record_event!(approve ? :sick_extension_approved : :sick_extension_rejected, by:)
    end
  end

  def record_event!(type, by:)
    leave_request.events.create!(event_type: type, actor: by, occurred_at: Time.current,
      from_status: LeaveRequest.statuses.fetch(leave_request.status), to_status: LeaveRequest.statuses.fetch(leave_request.status),
      comment: "Окончание: #{previous_ends_on.strftime('%d.%m.%Y')} → #{proposed_ends_on.strftime('%d.%m.%Y')}")
  end

  private

  def period_is_valid
    unless proposed_ends_on.is_a?(Date) && SupportedCalendarPeriod::DATES.cover?(proposed_ends_on) &&
        previous_ends_on.is_a?(Date) && proposed_ends_on > previous_ends_on
      errors.add(:proposed_ends_on, "должна быть позже подтверждённого окончания и в допустимом диапазоне дат")
    end
  end

  def retain_history
    errors.add(:base, "История продлений сохраняется")
    throw :abort
  end
end
