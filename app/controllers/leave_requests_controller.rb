class LeaveRequestsController < ApplicationController
  include HistoryPagination

  before_action :set_leave_request, only: %i[destroy return_from_childcare]

  def index
    @leave_requests = paginate_history(Current.user.leave_requests.includes(:leave_type, :leave_recalls, :legal_review, events: :actor))
  end

  def new
    @leave_request = Current.user.leave_requests.new
    @leave_request.start_time = "09:00"
    @leave_request.end_time = "18:00"
    @full_day = true
    if params[:resumes_request_id]
      require_identifier_fields!(params, :resumes_request_id)
      source = Current.user.leave_requests.find(params[:resumes_request_id])
      @leave_request.assign_attributes(resumes_request: source, leave_type: source.leave_type,
        child_born_on: source.child_born_on, care_relationship: source.care_relationship)
    end
    load_form_options
  end

  def create
    @leave_request = Current.user.leave_requests.new(leave_request_params)

    if @leave_request.submit
      redirect_to leave_requests_path, notice: "Заявка создана."
    else
      render_new_with_errors
    end
  rescue ActiveRecord::StatementInvalid => error
    if error.cause.is_a?(PG::ExclusionViolation)
      conflict = @leave_request.overlapping_active_request
      @leave_request.errors.add(:base, LeaveRequest.overlap_error_message(conflict))
    elsif error.cause.is_a?(PG::UniqueViolation) &&
        error.cause.result.error_field(PG::Result::PG_DIAG_CONSTRAINT_NAME) == "leave_requests_one_birthday_per_year"
      @leave_request.errors.add(:base, "Выходной в день рождения можно использовать только один раз за календарный год")
    else
      raise
    end
    render_new_with_errors
  end

  def destroy
    @leave_request.cancel!(by: Current.user)
    redirect_to leave_requests_path, notice: "Заявка отменена.", status: :see_other
  rescue LeaveRequest::InvalidTransition => error
    redirect_to leave_requests_path, alert: error.message, status: :see_other
  end

  def return_from_childcare
    attributes = params.expect(childcare_return: %i[return_on confirmed])
    require_string_fields!(attributes, :return_on, :confirmed)
    unless attributes[:confirmed] == "1"
      raise LeaveRequest::InvalidTransition, "Подтвердите заявление о выходе"
    end
    date = Date.iso8601(attributes[:return_on]) if attributes[:return_on]&.match?(/\A\d{4}-\d{2}-\d{2}\z/)
    @leave_request.return_from_childcare!(by: Current.user, return_on: date)
    redirect_to leave_requests_path, notice: "Заявление о выходе сохранено. Согласование руководителя не требуется.", status: :see_other
  rescue Date::Error, LeaveRequest::InvalidTransition => error
    redirect_to leave_requests_path, alert: error.message, status: :see_other
  rescue LeaveRequest::ReviewNotAuthorized
    head :not_found
  end

  private

  def set_leave_request
    @leave_request = Current.user.leave_requests.find(params[:id])
  end

  def leave_request_params
    fields = %i[leave_type_id starts_on ends_on start_time end_time full_day employee_comment
      child_born_on care_relationship resumes_request_id]
    raw = params[:leave_request]
    if raw.is_a?(ActionController::Parameters)
      require_string_fields!(raw, :child_born_on, :care_relationship)
      require_identifier_fields!(raw, :resumes_request_id)
    end
    if raw.is_a?(ActionController::Parameters) && (raw.key?(:start_part) || raw.key?(:end_part))
      raise ActionController::BadRequest, "Use exact start and end times"
    end
    require_known_fields!(raw, *fields, container: "leave_request",
      example: '{"leave_request":{"leave_type_id":"1","starts_on":"2026-11-10",' \
        '"ends_on":"2026-11-12"}}')
    attributes = params.expect(leave_request: fields)
    full_day = attributes.delete(:full_day)
    raise ActionController::BadRequest, "Invalid full day value" unless [ nil, "0", "1" ].include?(full_day)

    @full_day = full_day == "1"
    if @full_day
      attributes[:start_time] = "00:00"
      attributes[:end_time] = "24:00"
    else
      attributes[:start_time] = "00:00" unless attributes.key?(:start_time)
      attributes[:end_time] = "24:00" unless attributes.key?(:end_time)
    end
    require_string_fields!(
      attributes,
      :starts_on, :ends_on, :start_time, :end_time, :employee_comment, :child_born_on, :care_relationship
    )
    require_identifier_fields!(attributes, :leave_type_id, :resumes_request_id)
    birthday_id = LeaveType.find_by(code: LeaveType::BIRTHDAY_CODE)&.id
    if attributes[:leave_type_id].to_s == birthday_id.to_s && birthday_id && attributes[:ends_on].blank?
      attributes[:ends_on] = attributes[:starts_on]
    end
    if attributes[:resumes_request_id].present?
      Current.user.leave_requests.find(attributes[:resumes_request_id])
    end
    @date_inputs = attributes.slice(:starts_on, :ends_on)
    %i[starts_on ends_on].each do |field|
      value = attributes[field]
      next unless value&.match?(/\A\d{2}\.\d{2}\.\d{4}\z/)

      attributes[field] = Date.strptime(value, "%d.%m.%Y").iso8601
    rescue Date::Error
      attributes[field] = ""
    end
    attributes
  end

  def render_new_with_errors
    load_form_options
    respond_to do |format|
      format.html { render :new, status: :unprocessable_entity }
      format.json { render json: { errors: @leave_request.errors.full_messages }, status: :unprocessable_entity }
    end
  end

  def load_form_options
    @leave_types = LeaveType.where(active: true).order(:name)
    @available_years = FederalCalendar.where(year: CalendarWindow::YEARS).order(:year).pluck(:year)
    if Current.user.region_id
      @available_years &= RegionalCalendar.where(region_id: Current.user.region_id, complete: true).pluck(:year)
    end
    @public_holidays = @available_years.flat_map do |year|
      PublicHoliday.dates_for_year(year, region_id: Current.user.region_id).to_a
    end
  end
end
