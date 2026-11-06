module Admin
  class FamilyLeavesController < ApplicationController
    include HistoryPagination
    include LegalReviewParameters
    before_action :require_administrator
    before_action :set_request, except: :index

    def index
      @requests = paginate_history(LeaveRequest.joins(:leave_type)
        .where(leave_types: { code: %w[MATERNITY CHILDCARE] })
        .includes(:employee, :leave_type))
    end

    def show
    end

    def register
      @leave_request.register_family!(by: Current.user, legal_review: legal_review_params)
      redirect_to admin_family_leave_path(@leave_request), notice: "Семейный отпуск зарегистрирован.", status: :see_other
    rescue ActiveRecord::RecordInvalid => error
      render_error(error.record.errors.full_messages.to_sentence)
    rescue LeaveRequest::ReviewNotAuthorized
      head :forbidden
    rescue LeaveRequest::InvalidTransition => error
      render_error(error.message)
    end

    def clarify
      require_string_fields!(params, :review_comment)
      @leave_request.request_clarification!(by: Current.user, comment: params[:review_comment])
      redirect_to admin_family_leave_path(@leave_request), notice: "Запрос уточнения сохранён.", status: :see_other
    rescue ActiveRecord::RecordInvalid => error
      render_error(error.record.errors.full_messages.to_sentence)
    rescue LeaveRequest::ReviewNotAuthorized
      head :forbidden
    rescue LeaveRequest::InvalidTransition => error
      render_error(error.message)
    end

    private

    def require_administrator
      head :forbidden unless Current.user.administrator?
    end

    def set_request
      @leave_request = LeaveRequest.joins(:leave_type)
        .where(leave_types: { code: %w[MATERNITY CHILDCARE] }).find(params[:id])
    end

    def render_error(message)
      flash.now[:alert] = message
      @leave_request.reload
      render :show, status: :unprocessable_entity
    end
  end
end
