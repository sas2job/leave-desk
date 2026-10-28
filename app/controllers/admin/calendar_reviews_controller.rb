module Admin
  class CalendarReviewsController < ApplicationController
    before_action :require_administrator

    def index
      @requests = LeaveRequest.where(calendar_unverified: true)
        .includes(:employee, :leave_type).order(:starts_on, :id)
      request_years = @requests.flat_map(&:calendar_years).uniq
      @configured_years = FederalCalendar.where(year: request_years)
        .pluck(:year).to_set
    end

    def update
      LeaveRequest.find(params[:id]).reconcile_calendar!(by: Current.user)
      redirect_to admin_calendar_reviews_path, notice: "Расчёт заявки проверен и записан в историю."
    rescue LeaveRequest::InvalidTransition => error
      redirect_to admin_calendar_reviews_path, alert: error.message
    end

    private

    def require_administrator
      head :forbidden unless Current.user.administrator?
    end
  end
end
