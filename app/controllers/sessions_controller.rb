class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  def new
  end

  def create
    @email_address = params[:email_address] if params[:email_address].is_a?(String)
    limiter = LoginRateLimiter.new(ip_address: request.remote_ip, email_address: @email_address)
    if limiter.blocked?
      redirect_to new_session_path, alert: "Повторите попытку позже."
      return
    end

    password = params[:password]
    user = User.authenticate_by(email_address: @email_address, password:) if
      @email_address.present? && password.is_a?(String)

    if user&.active? && start_new_session_for(user)
      redirect_to after_authentication_url
    else
      limiter.record_failure!
      flash.now[:alert] = "Неверный адрес электронной почты или пароль."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end
end
