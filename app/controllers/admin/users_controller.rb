module Admin
  class UsersController < ApplicationController
    before_action :require_administrator
    before_action :set_user, only: :edit
    before_action :set_manager_options, only: %i[new edit]

    def index
      @users = User.includes(:manager, :region).order(:name, :id)
    end

    def new
      @user = User.new(active: true)
    end

    def create
      attributes = user_params
      @user = User.new(attributes)

      if @user.save
        redirect_to admin_users_path, notice: "Сотрудник создан."
      else
        set_manager_options
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      attributes = user_params
      attributes = attributes.except(:password, :password_confirmation) if attributes[:password].blank?
      set_user

      if @user.update(attributes)
        redirect_to admin_users_path, notice: "Сотрудник обновлён."
      else
        set_manager_options
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
      @region_options = Region.order(:name)
    end

    def user_params
      fields = %i[name email_address city region_id birthday_on password password_confirmation role manager_id active]
      raw = params[:user]
      require_known_fields!(raw, *fields, container: "user",
        example: '{"user":{"name":"Сотрудник","email_address":"user@example.test",' \
          '"city":"Казань","region_id":"1","password":"example-password",' \
          '"password_confirmation":"example-password","role":"employee","active":true}}')
      if raw.is_a?(ActionController::Parameters)
        require_string_fields!(raw,
          :name, :email_address, :city, :birthday_on, :password, :password_confirmation, :role)
        require_identifier_fields!(raw, :manager_id, :region_id)
      end
      attributes = params.expect(user: fields)
      require_string_fields!(
        attributes,
        :name, :email_address, :city, :birthday_on, :password, :password_confirmation, :role
      )
      require_identifier_fields!(attributes, :manager_id, :region_id)
    end
  end
end
