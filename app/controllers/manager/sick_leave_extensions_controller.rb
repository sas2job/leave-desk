module Manager
  class SickLeaveExtensionsController < ApplicationController
    before_action :require_manager

    def approve
      review(approve: true)
    end

    def reject
      review(approve: false)
    end

    private

    def require_manager
      head :forbidden unless Current.user.manager?
    end

    def review(approve:)
      request = LeaveRequest.joins(:employee).where(users: { manager_id: Current.user.id }).find(params[:leave_request_id])
      extension = request.sick_leave_extensions.find(params[:id])
      extension.review!(by: Current.user, approve:)
      redirect_to manager_leave_requests_path(anchor: helpers.dom_id(request)), notice: approve ? "Продление подтверждено." : "Продление отклонено. Прежние даты сохранены."
    rescue LeaveRequest::ReviewNotAuthorized
      head :not_found
    rescue LeaveRequest::InvalidTransition => error
      redirect_to manager_leave_requests_path, alert: error.message
    rescue ActiveRecord::RecordInvalid => error
      redirect_to manager_leave_requests_path, alert: error.record.errors.full_messages.to_sentence
    rescue ActiveRecord::StatementInvalid => error
      raise unless error.cause.is_a?(PG::ExclusionViolation)
      redirect_to manager_leave_requests_path, alert: "Продление пересекается с другой активной заявкой. Подтверждённый период не изменён."
    end
  end
end
