module Payments
  class ProviderConfig < ApplicationRecord
    MODES = %w[test live].freeze
    CONNECTION_TEST_STATUSES = %w[success failed].freeze
    SHA256_HEX_PATTERN = /\A[0-9a-f]{64}\z/
    STRIPE_SECRET_KEY_PATTERN = /\A(?:sk|rk)_(test|live)_[A-Za-z0-9_]+\z/
    STRIPE_WEBHOOK_SECRET_PATTERN = /\Awhsec_[A-Za-z0-9_]+\z/
    REQUIRED_CHECKOUT_CREDENTIALS = {
      "fake" => [],
      "stripe" => %w[secret_key webhook_secret]
    }.freeze

    has_encrypted :credentials, type: :json, encrypted_attribute: :encrypted_credentials

    belongs_to :last_connection_tested_by, class_name: "User", optional: true

    validates :provider, presence: true, uniqueness: true
    validates :mode, inclusion: { in: MODES }, allow_nil: true
    validates :last_connection_test_status,
      inclusion: { in: CONNECTION_TEST_STATUSES },
      allow_nil: true
    validates :last_connection_test_mode, inclusion: { in: MODES }, allow_nil: true
    validates :account_fingerprint,
      format: { with: SHA256_HEX_PATTERN },
      allow_nil: true
    validates :last_connection_test_credential_revision,
      format: { with: SHA256_HEX_PATTERN },
      allow_nil: true

    scope :enabled_providers, -> { where(enabled: true) }

    def self.for_provider(provider)
      find_by(provider: provider)
    end

    def self.checkout_ready_providers
      return [ developer_mode_fake_config ] if Payments::Provider.developer_mode_fake_only?

      enabled_providers.select(&:checkout_ready?)
    end

    def self.checkout_config_for(provider)
      if Payments::Provider.developer_mode_fake_only?
        return unless provider.to_s == "fake"

        return developer_mode_fake_config
      end

      config = enabled_providers.find_by(provider: provider.to_s)
      config if config&.checkout_ready?
    end

    def credentials_hash
      credentials.is_a?(Hash) ? credentials : {}
    end

    def credential_configured?(key)
      credentials_hash.stringify_keys[key.to_s].present?
    end

    def credentials_complete?
      required_keys = REQUIRED_CHECKOUT_CREDENTIALS[provider]
      return false unless required_keys

      required_keys.all? { |key| credential_configured?(key) }
    end

    def detected_mode
      return unless provider == "stripe"

      credentials_hash.stringify_keys["secret_key"].to_s[
        STRIPE_SECRET_KEY_PATTERN,
        1
      ]
    end

    def effective_mode
      mode.presence_in(MODES) || detected_mode || "test"
    end

    def mode_consistent?
      detected_mode.blank? || detected_mode == effective_mode
    end

    def configuration_complete?
      credentials_complete? && mode_consistent?
    end

    def safe_configuration_state
      {
        provider: provider,
        enabled: enabled?,
        mode: effective_mode,
        mode_explicit: mode.present?,
        configuration_complete: configuration_complete?,
        checkout_ready: checkout_ready?,
        account_bound: stripe_account_bound?,
        connection_test_current: connection_test_current?,
        secret_key_configured: credential_configured?("secret_key"),
        webhook_secret_configured: credential_configured?("webhook_secret")
      }
    end

    def credential_revision
      Digest::SHA256.hexdigest(encrypted_credentials.to_s)
    end

    def stripe_account_bound?
      provider == "stripe" &&
        account_fingerprint.to_s.match?(SHA256_HEX_PATTERN)
    end

    def connection_test_current?
      return false unless provider == "stripe"
      return false unless last_connection_test_status == "success"
      return false unless stripe_account_bound?
      return false unless last_connection_test_mode == effective_mode

      secure_digest_match?(
        last_connection_test_credential_revision,
        credential_revision
      )
    end

    def checkout_ready?
      if provider == "fake" && Payments::Provider.developer_mode_fake_only?
        return true
      end

      return false unless enabled?
      return false if provider == "fake" && Rails.env.production?
      return false unless configuration_complete?
      return false if provider == "stripe" && !connection_test_current?

      true
    end

    def reconciliation_ready?
      provider == "stripe" &&
        configuration_complete? &&
        connection_test_current?
    end

    def self.developer_mode_fake_config
      new(provider: "fake", enabled: true, mode: "test")
    end
    private_class_method :developer_mode_fake_config

    private

    def secure_digest_match?(left, right)
      left = left.to_s
      right = right.to_s
      left.bytesize == right.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(left, right)
    end
  end
end
