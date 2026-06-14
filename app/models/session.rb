class Session < ApplicationRecord
  belongs_to :user

  attr_reader :raw_token

  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true

  scope :active, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }
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
    revoked_at.nil? && expires_at > Time.current
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

  def touch_activity!
    update_column(:last_active_at, Time.current)
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
