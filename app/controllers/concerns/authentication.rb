module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private

  def authenticated?
    resume_session
  end

  def require_authentication
    resume_session || request_authentication
  end

  def resume_session
    return Current.session if Current.session

    session_id = cookies.signed[:session_id]
    return unless session_id

    existing_session = Session.includes(:user).find_by(id: session_id)
    if existing_session&.user&.active? && !existing_session.expired?
      Current.session = existing_session
    else
      cookies.delete(:session_id)
      nil
    end
  end

  def request_authentication
    session[:return_to_after_authenticating] = request.url
    redirect_to new_session_path
  end

  def after_authentication_url
    session.delete(:return_to_after_authenticating) || root_url
  end

  def start_new_session_for(user)
    authenticated_password_digest = user.password_digest
    new_session = user.with_lock do
      if user.active? && user.password_digest == authenticated_password_digest
        user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip)
      end
    end
    return false unless new_session

    Current.session = new_session
    cookies.signed[:session_id] = {
      value: new_session.id,
      expires: Session::LIFETIME.from_now,
      httponly: true,
      same_site: :lax
    }
    true
  end

  def terminate_session
    Current.session&.destroy!
    cookies.delete(:session_id)
  end
end
