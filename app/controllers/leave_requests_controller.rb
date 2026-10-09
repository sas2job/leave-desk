class LeaveRequestsController < ApplicationController
  before_action :set_leave_request, only: :destroy

  def index
    @leave_requests = Current.user.leave_requests.includes(:leave_type).order(created_at: :desc)
  end

  def new
    @leave_request = Current.user.leave_requests.new
    @leave_types = LeaveType.where(active: true).order(:name)
  end

  def create
    @leave_request = Current.user.leave_requests.new(leave_request_params)

    if @leave_request.save
      redirect_to leave_requests_path, notice: "Заявка создана."
    else
      render_new_with_errors
    end
  rescue ActiveRecord::StatementInvalid => error
    raise unless error.cause.is_a?(PG::ExclusionViolation)

    @leave_request.errors.add(:base, "Период пересекается с другой активной заявкой")
    render_new_with_errors
  end

  def destroy
    @leave_request.cancel!
    redirect_to leave_requests_path, notice: "Заявка отменена.", status: :see_other
  rescue LeaveRequest::InvalidTransition => error
    redirect_to leave_requests_path, alert: error.message, status: :see_other
  end

  private

  def set_leave_request
    @leave_request = Current.user.leave_requests.find(params[:id])
  end

  def leave_request_params
    params.expect(leave_request: %i[leave_type_id starts_on ends_on day_part employee_comment])
  end

  def render_new_with_errors
    @leave_types = LeaveType.where(active: true).order(:name)
    render :new, status: :unprocessable_entity
  end
end
