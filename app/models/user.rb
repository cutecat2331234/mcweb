require "set"

class User < ApplicationRecord
  include HasPublicId
  include HasAvatar

  has_secure_password

  has_encrypted :totp_secret
  has_encrypted :recovery_codes, type: :array

  has_many :sessions, dependent: :destroy
  has_many :user_roles, dependent: :destroy
  has_many :roles, through: :user_roles
  has_many :group_memberships, class_name: "Community::GroupMembership", dependent: :destroy
  has_many :user_groups, through: :group_memberships, source: :user_group
  has_many :notifications, dependent: :destroy
  has_many :notification_preferences, dependent: :destroy
  has_many :user_badges, class_name: "Community::UserBadge", dependent: :destroy
  has_many :forum_warnings, class_name: "Community::UserWarning", dependent: :destroy
  has_many :forum_staff_notes, class_name: "Community::StaffNote", dependent: :destroy
    has_many :user_silences, class_name: "Community::UserSilence", dependent: :destroy
  has_many :forum_user_field_values, class_name: "Community::UserFieldValue", dependent: :destroy
    has_many :forum_saved_searches, class_name: "Community::SavedSearch", dependent: :destroy
    has_many :forum_unread_filter_presets, class_name: "Community::UnreadFilterPreset", dependent: :destroy
    has_many :forum_search_histories, class_name: "Community::SearchHistory", dependent: :destroy
    has_many :store_wishlist_filter_presets, class_name: "Commerce::WishlistFilterPreset", dependent: :destroy
    has_many :shipping_addresses, class_name: "Commerce::ShippingAddress", dependent: :destroy
    has_many :store_credit_transactions, class_name: "Commerce::StoreCreditTransaction", dependent: :destroy
    has_many :forum_point_accounts, class_name: "Community::PointAccount", dependent: :destroy
    has_many :forum_point_transactions, class_name: "Community::PointTransaction", dependent: :destroy
    has_many :memberships, class_name: "Commerce::UserMembership", dependent: :destroy
    has_many :entitlements, class_name: "Commerce::UserEntitlement", dependent: :destroy
  has_many :admin_module_grants, dependent: :destroy
  has_many :data_exports, class_name: "Identity::DataExport", dependent: :destroy
  has_many :created_retention_holds,
           class_name: "DataGovernance::RetentionHold",
           foreign_key: :created_by_id,
           dependent: :restrict_with_error
  has_many :deleted_content_lifecycle_records,
           class_name: "DataGovernance::ContentLifecycleRecord",
           foreign_key: :deleted_by_id,
           dependent: :nullify
  has_many :restored_content_lifecycle_records,
           class_name: "DataGovernance::ContentLifecycleRecord",
           foreign_key: :restored_by_id,
           dependent: :nullify
  has_many :purged_content_lifecycle_records,
           class_name: "DataGovernance::ContentLifecycleRecord",
           foreign_key: :purged_by_id,
           dependent: :nullify
  has_many :minecraft_identities, class_name: "Minecraft::Identity", dependent: :destroy
  has_many :minecraft_identity_links, class_name: "Minecraft::IdentityLink", dependent: :destroy
  has_many :minecraft_player_profiles, through: :minecraft_identity_links, source: :player_profile
  has_many :minecraft_primary_account_change_requests,
           class_name: "Minecraft::PrimaryAccountChangeRequest",
           dependent: :restrict_with_error
  has_many :minecraft_primary_account_change_events,
           class_name: "Minecraft::PrimaryAccountChangeEvent",
           dependent: :restrict_with_error

  enum :status, { active: "active", banned: "banned", deleted: "deleted" }, validate: true
  enum :account_type, { member: "member", staff: "staff", admin: "admin", owner: "owner" }, validate: true, prefix: :account
  DEVELOPER_MODE_PERSONAS = %w[owner moderator member].freeze

  validates :email, presence: true, uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :username, presence: true, uniqueness: { case_sensitive: false },
                       format: { with: /\A[a-zA-Z0-9_]+\z/ }, length: { minimum: 3, maximum: 32 }
  validates :locale,
            presence: true,
            inclusion: { in: ->(_) { Mcweb::LocaleResolver.available_locales } }
  validates :time_zone, presence: true
  validates :developer_mode_persona,
            inclusion: { in: DEVELOPER_MODE_PERSONAS },
            uniqueness: true,
            allow_nil: true
  validates :password,
            length: { minimum: 6 },
            allow_nil: true,
            unless: :developer_mode_relaxes_password_policy?

  before_validation :normalize_locale
  before_validation :track_developer_mode_relaxed_password, if: -> { password.present? }
  after_update :bump_permission_version_for_access_change,
               if: -> { saved_change_to_status? || saved_change_to_account_type? }

  scope :verified, -> { where(email_verified: true) }
  scope :not_banned, -> { where(status: :active) }

  private

  def bump_permission_version_for_access_change
    Identity::PermissionVersion.bump_users!([ id ])
  end

  public

  def permission?(key)
    return true if account_owner?

    authorization_permission_keys.include?(key.to_s)
  end

  # The version is bumped by role, role-permission, identity-group and account
  # access mutations. Old cache entries are therefore never reused after an
  # authorization change, while repeated checks in one request share one set.
  def authorization_permission_keys
    version = permission_version.to_i
    if @authorization_permission_version == version &&
        @authorization_permission_keys
      return @authorization_permission_keys
    end

    keys = Rails.cache.fetch(
      [ "identity", "effective-permissions", id, version ],
      expires_in: 1.hour
    ) do
      (permissions.pluck(:key) + group_permission_keys).map(&:to_s).uniq.sort
    end
    @authorization_permission_version = version
    @authorization_permission_keys = Array(keys).map(&:to_s).to_set.freeze
  end

  def group_permission_keys
    Community::UserGroup.permission_keys_for(self)
  end

  def can_access_admin?
    Identity::AccountAccess.can_access_admin?(self)
  end

  def admin_module_allowed?(module_key)
    Identity::AccountAccess.module_allowed?(self, module_key)
  end

  def available_store_credit_cents(exclude_order_id: nil)
    pending = Commerce::Order
      .where(user: self, status: %w[pending awaiting_payment])
      .where.not(store_credit_amount_cents: [ nil, 0 ])
    pending = pending.where.not(id: exclude_order_id) if exclude_order_id
    reserved = pending.sum(:store_credit_amount_cents)
    [ store_credit_cents.to_i - reserved, 0 ].max
  end

  def permissions
    Permission.joins(roles: :users).where(users: { id: id }).distinct
  end

  def banned?
    return false unless status == "banned"

    ban_expires_at.nil? || ban_expires_at.future?
  end

  # Shared eligibility predicate for HTTP sessions and long-lived realtime
  # connections. Expired temporary bans follow the existing #banned? behavior.
  def session_eligible?
    !deleted? &&
      !banned? &&
      (developer_mode_persona.blank? || Mcweb::DeveloperMode.enabled?)
  end

  def ban_active?
    return false unless banned?

    ban_expires_at.nil? || ban_expires_at > Time.current
  end

  def silenced?
    Community::UserSilence.silenced?(self)
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
    Session.where(id: sessions.active.select(:id)).find_each(&:revoke!)
    Administration::ApiKey.where(user: self, revoked_at: nil)
      .update_all(revoked_at: Time.current, updated_at: Time.current)
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
      developer_mode_email_verified: false,
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

  # Accepted clock drift (seconds) on either side of the current TOTP step.
  # Kept tight and consistent across login, confirm, and disable paths.
  TOTP_DRIFT_SECONDS = 15

  def self.verify_totp_code(secret, code, drift: TOTP_DRIFT_SECONDS)
    return false if secret.blank? || code.blank?

    ROTP::TOTP.new(secret).verify(code.to_s, drift_behind: drift, drift_ahead: drift).present?
  end

  def verify_totp(code)
    return false unless totp_enabled? && totp_secret.present?

    self.class.verify_totp_code(totp_secret, code)
  end

  def consume_recovery_code!(code)
    return false unless recovery_codes.present?

    normalized = code.to_s.strip.upcase
    consumed = false
    # Lock + reload so two concurrent logins can't both spend the same recovery code.
    with_lock do
      codes = Array(recovery_codes)
      next unless codes.include?(normalized)

      update!(recovery_codes: codes - [ normalized ])
      consumed = true
    end
    consumed
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

  def normalize_locale
    self.locale = Mcweb::LocaleResolver.normalize(locale) || locale.to_s
  end

  def developer_mode_relaxes_password_policy?
    Mcweb::DeveloperMode.allow?(:relax_password_policy)
  end

  def track_developer_mode_relaxed_password
    self.developer_mode_relaxed_password =
      developer_mode_relaxes_password_policy? && password.to_s.length < 6
  end

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
