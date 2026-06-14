class User < ApplicationRecord
  include HasPublicId
  include HasAvatar

  has_secure_password

  has_encrypted :totp_secret
  has_encrypted :recovery_codes, type: :array

  has_many :sessions, dependent: :destroy
  has_many :user_roles, dependent: :destroy
  has_many :roles, through: :user_roles
  has_many :notifications, dependent: :destroy
  has_many :notification_preferences, dependent: :destroy

  enum :status, { active: "active", banned: "banned", deleted: "deleted" }, validate: true

  validates :email, presence: true, uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :username, presence: true, uniqueness: { case_sensitive: false },
                       format: { with: /\A[a-zA-Z0-9_]+\z/ }, length: { minimum: 3, maximum: 32 }
  validates :locale, presence: true
  validates :time_zone, presence: true

  scope :verified, -> { where(email_verified: true) }
  scope :not_banned, -> { where(status: :active) }

  def permission?(key)
    roles.joins(:permissions).exists?(permissions: { key: key })
  end

  def permissions
    Permission.joins(roles: :users).where(users: { id: id }).distinct
  end

  def banned?
    status == "banned" || (ban_expires_at.present? && ban_expires_at > Time.current)
  end

  def ban_active?
    return false unless banned?

    ban_expires_at.nil? || ban_expires_at > Time.current
  end

  def ban!(reason: nil, expires_at: nil)
    update!(
      status: :banned,
      banned_at: Time.current,
      ban_reason: reason,
      ban_expires_at: expires_at
    )
  end

  def unban!
    update!(
      status: :active,
      banned_at: nil,
      ban_reason: nil,
      ban_expires_at: nil
    )
  end

  def soft_delete!
    update!(status: :deleted, deleted_at: Time.current)
  end

  def generate_email_verification_token!
    token = SecureRandom.urlsafe_base64(32)
    update!(
      email_verification_token_digest: digest_token(token),
      email_verification_sent_at: Time.current
    )
    token
  end

  def verify_email!(token)
    return false unless email_verification_token_digest == digest_token(token)

    update!(
      email_verified: true,
      email_verified_at: Time.current,
      email_verification_token_digest: nil,
      email_verification_sent_at: nil
    )
    true
  end

  def generate_password_reset_token!
    token = SecureRandom.urlsafe_base64(32)
    update!(
      password_reset_token_digest: digest_token(token),
      password_reset_sent_at: Time.current
    )
    token
  end

  def reset_password!(token, new_password)
    return false unless password_reset_token_digest == digest_token(token)
    return false if password_reset_sent_at < 1.hour.ago

    self.password = new_password
    self.password_reset_token_digest = nil
    self.password_reset_sent_at = nil
    save!
    true
  end

  def setup_totp!
    secret = ROTP::Base32.random
    self.totp_secret = secret
    self.recovery_codes = generate_recovery_codes
    save!
    ROTP::TOTP.new(secret, issuer: "Mcweb")
  end

  def verify_totp(code)
    return false unless totp_enabled? && totp_secret.present?

    totp = ROTP::TOTP.new(totp_secret)
    totp.verify(code, drift_behind: 30, drift_ahead: 30)
  end

  def consume_recovery_code!(code)
    return false unless recovery_codes.present?

    normalized = code.to_s.strip.upcase
    return false unless recovery_codes.include?(normalized)

    self.recovery_codes = recovery_codes - [ normalized ]
    save!
    true
  end

  def record_failed_login!
    increment!(:failed_login_count)
    lock_account! if failed_login_count >= 5
  end

  def reset_failed_logins!
    update!(failed_login_count: 0, locked_until: nil)
  end

  def account_locked?
    locked_until.present? && locked_until > Time.current
  end

  private

  def digest_token(token)
    Digest::SHA256.hexdigest(token)
  end

  def generate_recovery_codes
    10.times.map { SecureRandom.hex(4).upcase }
  end

  def lock_account!
    update!(locked_until: 30.minutes.from_now)
  end
end
