module AnnualLeaveAccounting
  extend ActiveSupport::Concern

  included do
    has_many :annual_leave_bookings, dependent: :restrict_with_exception
    after_create :reserve_submitted_annual_leave
    before_update :remember_cancelled_annual_usage
    after_update :refresh_annual_leave_booking
  end

  def annual_requested_minutes
    duration_minutes || duration_half_days.to_i * 720
  end

  def annual_used_minutes(on: employee_today)
    return annual_cancelled_used_minutes if cancelled?
    return 0 if pending? || rejected? || starts_on > on
    return annual_charge_minutes if effective_ends_on <= on

    portion = dup
    portion.ends_on = on
    portion.end_minute = 1440 if precise_time?
    portion.end_part = :afternoon
    value = precise_time? ? portion.calendar_duration_in_minutes : portion.calendar_duration_in_days.to_f * 1440
    [ value.to_i, annual_charge_minutes ].min
  end

  def reserve_annual_leave!
    allocate_annual_leave!(:reserved, annual_requested_minutes)
  end

  private

  def reserve_submitted_annual_leave
    reserve_annual_leave! if annual_leave? && employee_submission?
  end

  def remember_cancelled_annual_usage
    return unless annual_leave? && will_save_change_to_status? && cancelled? && status_in_database == "approved"
    previous = self.class.find(id)
    self.annual_cancelled_used_minutes = previous.annual_used_minutes
  end

  def refresh_annual_leave_booking
    return unless annual_leave? && annual_leave_bookings.exists?
    return unless (saved_changes.keys & %w[status duration_minutes duration_half_days recalled_on annual_cancelled_used_minutes]).any?
    state = pending? ? :reserved : :committed
    allocate_annual_leave!(state, annual_charge_minutes)
  end

  def annual_charge_minutes
    return annual_cancelled_used_minutes if cancelled?
    return 0 if rejected?
    if recalled?
      unused = leave_recalls.confirmed.pick(:unused_days).to_i * 1440
      return [ annual_requested_minutes - unused, 0 ].max
    end
    annual_requested_minutes
  end

  def allocate_annual_leave!(state, required)
    employee.with_lock do
      years = employee.annual_leave_years.order(:starts_on, :id).lock.to_a
      previous = annual_leave_bookings.order(:id).to_a
      by_year = years.index_by(&:id)
      previous.each do |booking|
        year = by_year.fetch(booking.annual_leave_year_id)
        year.reserved_minutes -= booking.minutes if booking.booking_reserved?
        year.committed_minutes -= booking.minutes if booking.booking_committed?
        booking.assign_attributes(minutes: 0, status: :released)
      end
      eligible = years.select { |year| year.starts_on <= starts_on }
      available = eligible.sum(&:available_minutes)
      if required > available
        message = if eligible.empty?
          "Остаток ежегодного отпуска не настроен. Обратитесь к руководителю или администратору."
        else
          "Недостаточно дней ежегодного отпуска: доступно #{available / 1440.0}, требуется #{required / 1440.0}. Ожидающие заявки тоже резервируют дни."
        end
        errors.add(:base, message)
        raise ActiveRecord::RecordInvalid, self
      end
      remaining = required
      eligible.each do |year|
        break unless remaining.positive?
        amount = [ year.available_minutes, remaining ].min
        next unless amount.positive?
        booking = previous.find { |item| item.annual_leave_year_id == year.id } || annual_leave_bookings.build(annual_leave_year: year)
        previous << booking unless previous.include?(booking)
        booking.assign_attributes(minutes: amount, status: state)
        state == :reserved ? year.reserved_minutes += amount : year.committed_minutes += amount
        remaining -= amount
      end
      years.each { |year| year.save! if year.changed? }
      previous.each { |booking| booking.save! if booking.new_record? || booking.changed? }
    end
  end
end
