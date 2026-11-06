module ApplicationHelper
  LEAVE_REQUEST_STATUS_LABELS = {
    "pending" => "На рассмотрении",
    "approved" => "Одобрена",
    "rejected" => "Отклонена",
    "cancelled" => "Отменена",
    "recalled" => "Отозвана из отпуска",
    "interrupted" => "Отпуск по уходу прерван"
  }.freeze
  LEAVE_REQUEST_EVENT_LABELS = {
    "created" => "Заявка создана",
    "approved" => "Заявка одобрена",
    "rejected" => "Заявка отклонена",
    "cancelled" => "Заявка отменена",
    "calendar_unverified" => "Заявка требует проверки календаря",
    "calendar_reconciled" => "Заявка проверена по календарю",
    "recall_proposed" => "Заявка получила предложение об отзыве",
    "recall_consented" => "Заявка: сотрудник согласился на отзыв",
    "recall_declined" => "Заявка: сотрудник отказался от отзыва",
    "recall_withdrawn" => "Заявка: предложение об отзыве отозвано",
    "recalled" => "Заявка: отзыв из отпуска оформлен",
    "statutory_registered" => "Заявка: семейный отпуск зарегистрирован",
    "childcare_returned" => "Заявка: работник заявил о выходе из отпуска по уходу",
    "statutory_clarification" => "Заявка: требуется уточнение кадровых документов"
  }.freeze

  def leave_request_status_label(leave_request)
    if leave_request.family_leave? && Current.user&.manager? && Current.user.id != leave_request.employee_id && leave_request.interrupted?
      return "Отсутствие завершено"
    end
    return "Ожидает кадровой регистрации" if leave_request.family_leave? && leave_request.pending?
    LEAVE_REQUEST_STATUS_LABELS.fetch(leave_request.status)
  end

  def team_leave_type_name(request)
    request.family_leave? ? "Длительное отсутствие" : request.leave_type.name
  end

  def care_relationship_label(value)
    { "mother" => "Мать / усыновительница", "father" => "Отец / усыновитель",
      "relative" => "Другой родственник", "guardian" => "Опекун", "foster_parent" => "Приёмный родитель" }.fetch(value, "Не указано")
  end

  def format_date(date)
    date.strftime("%d.%m.%Y")
  end

  def format_duration(days)
    days.to_s.tr(".", ",")
  end

  def format_leave_duration(request)
    return "#{format_duration(request.duration_in_days)} дн." unless request.precise_time?

    format_duration_minutes(request.duration_minutes)
  end

  def format_calendar_duration(request)
    return "#{format_duration(request.calendar_duration_in_days)} дн." unless request.precise_time?

    format_duration_minutes(request.calendar_duration_in_minutes)
  end

  def format_duration_minutes(total_minutes)
    days, remaining = total_minutes.divmod(LeaveRequest::MINUTES_PER_DAY)
    hours, minutes = remaining.divmod(60)
    parts = []
    parts << "#{days} дн." if days.positive?
    parts << "#{hours} ч" if hours.positive?
    parts << "#{minutes} мин" if minutes.positive?
    parts.empty? ? "0 мин" : parts.join(" ")
  end

  def leave_request_event_label(event)
    LEAVE_REQUEST_EVENT_LABELS.fetch(event.event_type)
  end

  def leave_request_notification_label(event)
    if event.leave_request.family_leave? && Current.user.manager? && Current.user.id != event.leave_request.employee_id
      return "Заявка №#{event.leave_request.id}: дата окончания отсутствия обновлена"
    end
    leave_request_event_label(event).sub(/\AЗаявка(?= |:)/, "Заявка №#{event.leave_request.id}")
  end

  def notification_request_path(leave_request, event_type: nil)
    if leave_request.family_leave? && Current.user.administrator? && leave_request.employee_id != Current.user.id
      return admin_family_leave_path(leave_request)
    end
    if Current.user.administrator? && event_type == "calendar_unverified"
      return admin_calendar_reviews_path(anchor: dom_id(leave_request))
    end

    if leave_request.employee_id == Current.user.id
      leave_requests_path(before: leave_request.id + 1, anchor: dom_id(leave_request))
    else
      manager_leave_requests_path(before: leave_request.id + 1, anchor: dom_id(leave_request))
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
