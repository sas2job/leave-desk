module Admin
  class LeaveTypesController < ApplicationController
    before_action :require_administrator
    before_action :set_leave_type, only: %i[edit update]

    def index
      @leave_types = LeaveType.order(:name)
    end

    def new
      @leave_type = LeaveType.new
    end

    def create
      @leave_type = LeaveType.new(leave_type_params)

      if @leave_type.save
        redirect_to admin_leave_types_path, notice: "Вид отпуска создан."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @leave_type.update(leave_type_params)
        redirect_to admin_leave_types_path, notice: "Вид отпуска обновлён."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def require_administrator
      head :forbidden unless Current.user.administrator?
    end

    def set_leave_type
      @leave_type = LeaveType.find(params[:id])
    end

    def leave_type_params
      params.expect(leave_type: %i[name code holiday_handling active])
    end
  end
end
