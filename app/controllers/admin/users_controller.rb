module Admin
  class UsersController < ApplicationController
    before_action :require_administrator
    before_action :set_user, only: %i[edit update]
    before_action :set_manager_options, only: %i[new create edit update]

    def index
      @users = User.includes(:manager).order(:name, :id)
    end

    def new
      @user = User.new(active: true)
    end

    def create
      @user = User.new(user_params)

      if @user.save
        redirect_to admin_users_path, notice: "Сотрудник создан."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      attributes = user_params
      attributes = attributes.except(:password, :password_confirmation) if attributes[:password].blank?

      if @user.update(attributes)
        redirect_to admin_users_path, notice: "Сотрудник обновлён."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def require_administrator
      head :forbidden unless Current.user.administrator?
    end

    def set_user
      @user = User.find(params[:id])
    end

    def set_manager_options
      @manager_options = User.manager.where(active: true).where.not(id: @user&.id).order(:name)
    end

    def user_params
      params.expect(user: %i[name email_address birthday_on password password_confirmation role manager_id active])
    end
  end
end
