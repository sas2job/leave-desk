class LeaveRequestsController < ApplicationController
  include HistoryPagination

  before_action :set_leave_request, only: :destroy

  def index
    @leave_requests = paginate_history(Current.user.leave_requests.includes(:leave_type, events: :actor))
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
    @leave_request.cancel!(by: Current.user)
    redirect_to leave_requests_path, notice: "Заявка отменена.", status: :see_other
  rescue LeaveRequest::InvalidTransition => error
    redirect_to leave_requests_path, alert: error.message, status: :see_other
  end

  private

  def set_leave_request
    @leave_request = Current.user.leave_requests.find(params[:id])
  end

  def leave_request_params
    attributes = params.expect(leave_request: %i[leave_type_id starts_on start_part ends_on end_part employee_comment])
    require_string_fields!(
      attributes,
      :starts_on, :start_part, :ends_on, :end_part, :employee_comment
    )
    require_identifier_fields!(attributes, :leave_type_id)
  end

  def render_new_with_errors
    @leave_types = LeaveType.where(active: true).order(:name)
    respond_to do |format|
      format.html { render :new, status: :unprocessable_entity }
      format.json { render json: { errors: @leave_request.errors.full_messages }, status: :unprocessable_entity }
    end
  end
end
