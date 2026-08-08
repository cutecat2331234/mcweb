class Session < ApplicationRecord
  ACTIVITY_TOUCH_INTERVAL = 2.minutes
  belongs_to :user

  attr_reader :raw_token

  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true

  scope :active, -> {
    relation = where(revoked_at: nil).where("expires_at > ?", Time.current)
    Mcweb::DeveloperMode.enabled? ? relation : relation.where(developer_mode: false)
  }
  scope :expired, -> { where("expires_at <= ?", Time.current) }

  before_validation :generate_token, on: :create
  before_validation :set_expiry, on: :create

  def self.find_by_token(token)
    find_by(token_digest: digest_token(token))
  end

  def self.digest_token(token)
    Digest::SHA256.hexdigest(token)
  end

  def active?
    revoked_at.nil? &&
      expires_at > Time.current &&
      (!developer_mode? || Mcweb::DeveloperMode.enabled?)
  end

  def expired?
    expires_at <= Time.current
  end

  def revoked?
    revoked_at.present?
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  def touch_activity!(at: Time.current)
    cutoff = at - ACTIVITY_TOUCH_INTERVAL
    return false if last_active_at && last_active_at > cutoff

    updated = self.class
      .where(id: id)
      .where("last_active_at IS NULL OR last_active_at <= ?", cutoff)
      .update_all(last_active_at: at)
    if updated.positive?
      self.last_active_at = at
      clear_attribute_changes([ :last_active_at ])
    end
    updated.positive?
  end

  private

  def generate_token
    return if token_digest.present?

    @raw_token = SecureRandom.urlsafe_base64(32)
    self.token_digest = self.class.digest_token(@raw_token)
  end

  def set_expiry
    self.expires_at ||= remember_me? ? 30.days.from_now : 24.hours.from_now
  end
end
