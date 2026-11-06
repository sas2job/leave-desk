class LeaveRecallsController < ApplicationController
  before_action :require_manager, only: %i[new create confirm]
  before_action :set_leave_request
  before_action :set_recall, except: %i[new create]

  rescue_from LeaveRecall::NotAuthorized, with: -> { head :not_found }
  rescue_from LeaveRecall::InvalidTransition, with: :render_recall_error
  rescue_from ActiveRecord::RecordInvalid, with: :render_recall_error

  def new
    @recall = @leave_request.leave_recalls.new
  end

  def create
    attributes = recall_params(:return_on, :reason, :eligibility_confirmed)
    @recall = LeaveRecall.propose!(leave_request: @leave_request, by: Current.user,
      return_on: parse_date(attributes[:return_on]), reason: attributes[:reason],
      eligibility_confirmed: attributes[:eligibility_confirmed] == "1")
    redirect_to leave_request_recall_path(@leave_request, @recall),
      notice: "Предложение направлено сотруднику. До согласия и приказа отпуск продолжается.", status: :see_other
  end

  def show
  end

  def consent
    attributes = recall_params(:consent_confirmed, :remainder_option, :remainder_preference)
    unless attributes[:consent_confirmed] == "1"
      raise LeaveRecall::InvalidTransition, "Для согласия установите отметку добровольного согласия"
    end
    @recall.consent!(by: Current.user, remainder_option: attributes[:remainder_option],
      remainder_preference: attributes[:remainder_preference])
    redirect_to_recall("Согласие сохранено. Отпуск изменится после оформления приказа.")
  end

  def decline
    @recall.decline!(by: Current.user)
    redirect_to_recall("Отказ сохранён. Отпуск продолжается без изменений.")
  end

  def withdraw
    @recall.withdraw!(by: Current.user)
    redirect_to_recall("Предложение об отзыве отозвано. Отпуск продолжается.")
  end

  def confirm
    attributes = recall_params(:order_number, :order_on, :consent_reference, :eligibility_confirmed)
    @recall.confirm!(by: Current.user, order_number: attributes[:order_number],
      order_on: parse_date(attributes[:order_on]), consent_reference: attributes[:consent_reference],
      eligibility_confirmed: attributes[:eligibility_confirmed] == "1")
    redirect_to_recall("Отзыв оформлен. Неиспользованная часть отпуска сохранена.")
  end

  private

  def require_manager
    head :forbidden unless Current.user.manager?
  end

  def set_leave_request
    requests = LeaveRequest.where(employee_id: Current.user.id)
    if Current.user.manager?
      managed = LeaveRequest.where(employee_id: Current.user.direct_reports.select(:id))
      requests = %w[new create confirm].include?(action_name) ? managed : requests.or(managed)
    end
    @leave_request = requests.find(params[:leave_request_id])
  end

  def set_recall
    @recall = @leave_request.leave_recalls.find(params[:id])
  end

  def recall_params(*fields)
    raw = params[:recall]
    require_known_fields!(raw, *fields, container: "recall", example: '{"recall":{}}')
    require_string_fields!(raw, *fields) if raw.is_a?(ActionController::Parameters)
    attributes = params.expect(recall: fields)
    require_string_fields!(attributes, *fields)
    attributes
  end

  def parse_date(value)
    Date.iso8601(value) if value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
  rescue Date::Error
    nil
  end

  def redirect_to_recall(notice)
    redirect_to leave_request_recall_path(@leave_request, @recall), notice:, status: :see_other
  end

  def render_recall_error(error)
    messages = error.is_a?(ActiveRecord::RecordInvalid) ? error.record.errors.full_messages : [ error.message ]
    respond_to do |format|
      format.json { render json: { errors: messages }, status: :unprocessable_entity }
      format.html do
        flash.now[:alert] = messages.to_sentence
        @recall = error.record if error.is_a?(ActiveRecord::RecordInvalid) && error.record.is_a?(LeaveRecall)
        @recall ||= @leave_request.leave_recalls.new
        @recall.reload if @recall.persisted?
        render @recall.persisted? ? :show : :new, status: :unprocessable_entity
      end
    end
  end
end
