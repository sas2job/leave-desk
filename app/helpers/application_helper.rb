module ApplicationHelper
  LEAVE_REQUEST_STATUS_LABELS = {
    "pending" => "На рассмотрении",
    "approved" => "Одобрена",
    "rejected" => "Отклонена",
    "cancelled" => "Отменена"
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
end
