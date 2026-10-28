class User < ApplicationRecord
  MINIMUM_PASSWORD_LENGTH = 12
  CITY_TIME_ZONES = {
    "Калининград" => "Europe/Kaliningrad",
    "Москва" => "Europe/Moscow",
    "Санкт-Петербург" => "Europe/Moscow",
    "Казань" => "Europe/Moscow",
    "Минск" => "Europe/Minsk",
    "Самара" => "Europe/Samara",
    "Екатеринбург" => "Asia/Yekaterinburg",
    "Пермь" => "Asia/Yekaterinburg",
    "Уфа" => "Asia/Yekaterinburg",
    "Омск" => "Asia/Omsk",
    "Новосибирск" => "Asia/Novosibirsk",
    "Барнаул" => "Asia/Barnaul",
    "Красноярск" => "Asia/Krasnoyarsk",
    "Иркутск" => "Asia/Irkutsk",
    "Братск" => "Asia/Irkutsk",
    "Якутск" => "Asia/Yakutsk",
    "Владивосток" => "Asia/Vladivostok",
    "Хабаровск" => "Asia/Vladivostok",
    "Магадан" => "Asia/Magadan",
    "Петропавловск-Камчатский" => "Asia/Kamchatka"
  }.freeze

  before_validation :set_time_zone_from_city

  has_secure_password

  enum :role, { employee: 0, manager: 1, administrator: 2 }, validate: true

  belongs_to :manager, class_name: "User", optional: true
  has_many :direct_reports, class_name: "User", foreign_key: :manager_id,
    inverse_of: :manager, dependent: :nullify
  has_many :leave_requests, foreign_key: :employee_id, inverse_of: :employee,
    dependent: :restrict_with_exception
  has_many :reviewed_leave_requests, class_name: "LeaveRequest",
    foreign_key: :reviewer_id, inverse_of: :reviewer,
    dependent: :restrict_with_exception
  has_many :sessions, dependent: :destroy
  has_many :notifications, foreign_key: :recipient_id, dependent: :destroy

  normalizes :email_address, with: ->(email) { email.strip.downcase }

  validates :name, presence: true
  validates :name, length: { maximum: 100 }, if: :will_save_change_to_name?
  validates :city, length: { maximum: 100 }, if: :will_save_change_to_city?
  validates :city, inclusion: { in: CITY_TIME_ZONES.keys }, allow_blank: true
  validates :time_zone, inclusion: { in: CITY_TIME_ZONES.values }
  validates :email_address, presence: true, uniqueness: { case_sensitive: false },
    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :email_address, length: { maximum: 254 }, if: :will_save_change_to_email_address?
  validates :password, length: { minimum: MINIMUM_PASSWORD_LENGTH }, allow_nil: true
  validate :password_has_no_nul
  validate :manager_is_active_manager
  validate :role_and_activity_support_direct_reports
  validate :retain_active_administrator
  validate :active_has_boolean_input
  validate :birthday_is_valid_if_supplied
  validate :manager_id_has_valid_syntax
  after_update :revoke_sessions_after_authentication_change,
    if: -> { saved_change_to_active? || saved_change_to_password_digest? }

  def password=(raw_password)
    @password_with_nul = raw_password.is_a?(String) && raw_password.include?("\0")
    if @password_with_nul
      @password = raw_password
    else
      super
    end
  end

  def birthday_in_year(year)
    return unless birthday_on.is_a?(Date)

    Date.new(year, birthday_on.month, birthday_on.day)
  rescue Date::Error
    nil
  end

  def save(**options)
    with_user_locks { super }
  end

  def save!(**options)
    with_user_locks { super }
  end

  private

  def set_time_zone_from_city
    self.time_zone = CITY_TIME_ZONES[city] if CITY_TIME_ZONES.key?(city)
  end

  def password_has_no_nul
    errors.add(:password, "содержит недопустимый символ") if @password_with_nul
  end

  def with_user_locks
    changing_role_or_activity = persisted? &&
      (will_save_change_to_role? || will_save_change_to_active?)
    lock_ids = []
    lock_ids << id if changing_role_or_activity
    assigning_manager = manager_id.present? && (new_record? || will_save_change_to_manager_id?)
    lock_ids << manager_id if assigning_manager
    return yield if lock_ids.empty?

    intended_changes = if changing_role_or_activity
      attributes_before_type_cast.slice(*changed_attribute_names_to_save)
    end

    self.class.transaction do
      if changing_role_or_activity
        self.class.uncached do
          self.class.administrator.where(active: true).order(:id).lock("FOR UPDATE").load
        end
      end
      locked_users = self.class.uncached do
        self.class.where(id: lock_ids.uniq).order(:id).lock("FOR UPDATE").index_by(&:id)
      end
      if changing_role_or_activity
        reload
        assign_attributes(intended_changes)
      end
      association(:manager).target = locked_users[manager_id] if assigning_manager
      yield
    end
  end

  def revoke_sessions_after_authentication_change
    sessions.delete_all
  end

  def manager_is_active_manager
    if manager_id.present? && manager.nil?
      errors.add(:manager, "не найден")
      return
    end
    return if manager.nil?

    errors.add(:manager, "не может совпадать с сотрудником") if manager == self
    unless manager.active? && manager.manager?
      errors.add(:manager, "должен быть активным руководителем")
    end
  end

  def active_has_boolean_input
    raw_active = attribute_before_type_cast("active")
    return if [ true, false, 1, 0, "1", "0", "true", "false" ].include?(raw_active)

    errors.add(:active, "должна быть указана как да или нет")
  end

  def birthday_is_valid_if_supplied
    raw_birthday = attribute_before_type_cast("birthday_on")
    return if raw_birthday.blank? || birthday_on.is_a?(Date)

    errors.add(:birthday_on, "содержит неверную дату")
  end

  def manager_id_has_valid_syntax
    raw_id = attribute_before_type_cast("manager_id")
    return if raw_id.blank?
    return if raw_id.is_a?(Integer) && raw_id.positive?
    return if raw_id.is_a?(String) && raw_id.match?(/\A[1-9]\d*\z/)

    errors.add(:manager, "должен быть выбран из списка")
  end

  def role_and_activity_support_direct_reports
    return if manager? && active?
    return unless persisted? && self.class.uncached { direct_reports.exists? }

    errors.add(:role, "нельзя изменить, пока у пользователя есть подчинённые") unless manager?
    errors.add(:active, "нельзя отключить, пока у пользователя есть подчинённые") unless active?
  end

  def retain_active_administrator
    return unless relinquishing_active_administrator?
    return unless self.class.uncached { self.class.administrator.where(active: true).count } <= 1

    errors.add(:base, "Нельзя удалить последнего активного администратора")
  end

  def relinquishing_active_administrator?
    persisted? && role_in_database == "administrator" && active_in_database &&
      (!administrator? || !active?)
  end
end
