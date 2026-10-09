class NotificationsController < ApplicationController
  before_action :set_notification, only: :update

  def index
    @notifications = Current.user.notifications.includes(leave_request_event: {
      leave_request: %i[employee leave_type]
    }).order(created_at: :desc)
  end

  def update
    @notification.mark_as_read!
    redirect_to notifications_path
  end

  def mark_all_read
    Current.user.notifications.unread.update_all(read_at: Time.current)
    redirect_to notifications_path, notice: "Уведомления отмечены прочитанными."
  end

  private

  def set_notification
    @notification = Current.user.notifications.find(params[:id])
  end
end
