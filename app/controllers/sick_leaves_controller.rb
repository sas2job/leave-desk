class SickLeavesController < ApplicationController
  before_action :set_leave_request

  def extend_period
    SickLeaveExtension.propose!(leave_request: @leave_request, by: Current.user,
      proposed_ends_on: sick_date(:proposed_ends_on))
    redirect_to leave_requests_path(anchor: helpers.dom_id(@leave_request)), notice: "Продление отправлено руководителю. Подтверждённый период пока не изменён."
  rescue LeaveRequest::InvalidTransition, ActiveRecord::RecordInvalid => error
    redirect_to leave_requests_path(anchor: helpers.dom_id(@leave_request)), alert: error_message(error)
  rescue LeaveRequest::ReviewNotAuthorized
    head :not_found
  end

  def close
    @leave_request.close_sick_leave!(by: Current.user, closed_on: sick_date(:closed_on))
    redirect_to leave_requests_path(anchor: helpers.dom_id(@leave_request)), notice: "Больничный закрыт. Фактическое окончание сохранено."
  rescue LeaveRequest::InvalidTransition, ActiveRecord::RecordInvalid => error
    redirect_to leave_requests_path(anchor: helpers.dom_id(@leave_request)), alert: error_message(error)
  rescue LeaveRequest::ReviewNotAuthorized
    head :not_found
  end

  private

  def set_leave_request
    @leave_request = Current.user.leave_requests.find(params[:leave_request_id])
  end

  def sick_date(field)
    require_known_fields!(params[:sick_leave], field, container: "sick_leave",
      example: "{\"sick_leave\":{\"#{field}\":\"2026-11-12\"}}")
    attributes = params.expect(sick_leave: [ field ])
    require_string_fields!(attributes, field)
    raw = attributes[field]
    return unless raw&.match?(/\A\d{4}-\d{2}-\d{2}\z/)
    Date.iso8601(raw)
  rescue Date::Error
    nil
  end

  def error_message(error)
    error.is_a?(ActiveRecord::RecordInvalid) ? error.record.errors.full_messages.to_sentence : error.message
  end
end
