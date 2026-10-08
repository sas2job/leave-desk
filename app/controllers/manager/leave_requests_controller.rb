module Manager
  class LeaveRequestsController < ApplicationController
    before_action :require_manager
    before_action :set_leave_request, only: %i[approve reject]

    def index
      @leave_requests = managed_leave_requests.includes(:employee, :leave_type)
        .order(created_at: :desc)
    end

    def approve
      @leave_request.approve!(by: Current.user, comment: params[:review_comment])
      redirect_to manager_leave_requests_path, notice: "Заявка одобрена."
    rescue LeaveRequest::InvalidTransition => error
      redirect_to manager_leave_requests_path, alert: error.message
    end

    def reject
      @leave_request.reject!(by: Current.user, comment: params[:review_comment])
      redirect_to manager_leave_requests_path, notice: "Заявка отклонена."
    rescue LeaveRequest::InvalidTransition => error
      redirect_to manager_leave_requests_path, alert: error.message
    end

    private

    def require_manager
      head :forbidden unless Current.user.manager?
    end

    def managed_leave_requests
      LeaveRequest.joins(:employee).where(users: { manager_id: Current.user.id })
    end

    def set_leave_request
      @leave_request = managed_leave_requests.find(params[:id])
    end
  end
end
