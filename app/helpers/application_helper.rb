module ApplicationHelper
  LEAVE_REQUEST_STATUS_LABELS = {
    "pending" => "На рассмотрении",
    "approved" => "Одобрена",
    "rejected" => "Отклонена",
    "cancelled" => "Отменена"
  }.freeze
  LEAVE_REQUEST_EVENT_LABELS = {
    "created" => "Заявка создана",
    "approved" => "Заявка одобрена",
    "rejected" => "Заявка отклонена",
    "cancelled" => "Заявка отменена",
    "calendar_unverified" => "Заявка требует проверки календаря",
    "calendar_reconciled" => "Заявка проверена по календарю"
  }.freeze

  def leave_request_status_label(leave_request)
    LEAVE_REQUEST_STATUS_LABELS.fetch(leave_request.status)
  end

  def format_date(date)
    date.strftime("%d.%m.%Y")
  end

  def format_duration(days)
    days.to_s.tr(".", ",")
  end

  def leave_request_event_label(event)
    LEAVE_REQUEST_EVENT_LABELS.fetch(event.event_type)
  end

  def leave_request_notification_label(event)
    leave_request_event_label(event).sub(/\AЗаявка /, "Заявка №#{event.leave_request.id} ")
  end

  def notification_request_path(leave_request, event_type: nil)
    if Current.user.administrator? && event_type == "calendar_unverified"
      return admin_calendar_reviews_path(anchor: dom_id(leave_request))
    end

    if leave_request.employee_id == Current.user.id
      leave_requests_path(anchor: dom_id(leave_request))
    else
      manager_leave_requests_path(anchor: dom_id(leave_request))
    end
  end

  def leave_request_event_transition(event)
    from = event.from_status && LEAVE_REQUEST_STATUS_LABELS.fetch(LeaveRequest.statuses.key(event.from_status))
    to = LEAVE_REQUEST_STATUS_LABELS.fetch(LeaveRequest.statuses.key(event.to_status))
    from ? "#{from} → #{to}" : to
  end

  def unread_notifications_count
    Current.user.notifications.unread.count
  end
end
