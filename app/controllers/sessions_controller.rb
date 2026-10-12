class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { redirect_to new_session_path, alert: "Повторите попытку позже." }

  def new
  end

  def create
    user = User.authenticate_by(params.permit(:email_address, :password))

    if user&.active? && start_new_session_for(user)
      redirect_to after_authentication_url
    else
      redirect_to new_session_path, alert: "Неверный адрес электронной почты или пароль."
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end
end
