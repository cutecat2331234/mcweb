# frozen_string_literal: true

module Payments
  class UpdateProviderConfiguration < ApplicationService
    PERMISSION = "store.payments.configure"
    PROVIDER = "stripe"
    CREDENTIAL_KEYS = %w[secret_key webhook_secret].freeze

    def initialize(actor:, attributes:, ip_address: nil, user_agent: nil)
      @actor = actor
      @attributes = attributes.to_h.symbolize_keys
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def call
      return forbidden_result unless @actor&.permission?(PERMISSION)

      result = nil
      Payments::ProviderConfig.transaction do
        config = Payments::ProviderConfig.find_or_create_by!(provider: PROVIDER)
        config.lock!
        before_state = config.safe_configuration_state
        prepared = prepare_attributes(config)

        if prepared.failure?
          result = prepared
          raise ActiveRecord::Rollback
        end

        config.assign_attributes(prepared.value)
        reset_connection_test!(config) if material_configuration_change?(config)
        config.save!

        Administration::AuditLogger.call(
          actor: @actor,
          action: "admin.payment_provider_configuration_updated",
          resource: config,
          metadata: {
            provider: config.provider,
            changed_fields: safe_changed_fields(before_state, config.safe_configuration_state)
          },
          before_state: before_state,
          after_state: config.safe_configuration_state,
          ip_address: @ip_address,
          user_agent: @user_agent
        )

        result = ServiceResult.success(config: config)
      end

      result
    rescue ActiveRecord::RecordInvalid
      ServiceResult.failure(
        error: :the_payment_provider_configuration_could_not_be_saved,
        code: "configuration_invalid"
      )
    end

    private

    def prepare_attributes(config)
      mode = @attributes[:mode].to_s
      unless Payments::ProviderConfig::MODES.include?(mode)
        return failure("Select either test or live mode.", "mode_invalid")
      end

      credentials = config.credentials_hash.stringify_keys.slice(*CREDENTIAL_KEYS)
      credential_result = apply_credential_changes(credentials)
      return credential_result if credential_result.failure?

      credentials = credential_result.value
      secret_key = credentials["secret_key"].to_s
      webhook_secret = credentials["webhook_secret"].to_s

      if secret_key.present?
        match = Payments::ProviderConfig::STRIPE_SECRET_KEY_PATTERN.match(secret_key)
        return failure("The Stripe secret key format is invalid.", "secret_key_invalid") unless match
        return failure("The Stripe secret key does not match the selected mode.", "mode_mismatch") unless match[1] == mode
      end

      if webhook_secret.present? &&
          !Payments::ProviderConfig::STRIPE_WEBHOOK_SECRET_PATTERN.match?(webhook_secret)
        return failure("The Stripe webhook signing secret format is invalid.", "webhook_secret_invalid")
      end

      enabled = ActiveModel::Type::Boolean.new.cast(@attributes[:enabled])
      if enabled && (secret_key.blank? || webhook_secret.blank?)
        return failure(
          "Configure both Stripe credentials before enabling checkout.",
          "credentials_incomplete"
        )
      end

      attributes = {
        mode: mode,
        enabled: enabled
      }
      current_credentials = config.credentials_hash.stringify_keys.slice(*CREDENTIAL_KEYS)
      attributes[:credentials] = credentials unless credentials == current_credentials

      ServiceResult.success(attributes)
    end

    def apply_credential_changes(credentials)
      CREDENTIAL_KEYS.each do |key|
        clear_key = :"clear_#{key}"
        replacement = @attributes[key.to_sym].to_s.strip
        clearing = ActiveModel::Type::Boolean.new.cast(@attributes[clear_key])

        if clearing && replacement.present?
          return failure(
            "A credential cannot be replaced and removed in the same request.",
            "credential_change_conflict"
          )
        end

        if clearing
          credentials.delete(key)
        elsif replacement.present?
          credentials[key] = replacement
        end
      end

      ServiceResult.success(credentials)
    end

    def material_configuration_change?(config)
      config.will_save_change_to_mode? ||
        config.will_save_change_to_encrypted_credentials?
    end

    def reset_connection_test!(config)
      config.assign_attributes(
        last_connection_tested_at: nil,
        last_connection_test_status: nil,
        last_connection_test_error_code: nil,
        last_connection_test_mode: nil,
        last_connection_tested_by: nil,
        last_connection_test_credential_revision: nil
      )
    end

    def safe_changed_fields(before_state, after_state)
      after_state.keys.filter_map do |key|
        key.to_s unless before_state[key] == after_state[key]
      end
    end

    def failure(message, code)
      ServiceResult.failure(error: message, code: code)
    end

    def forbidden_result
      failure(
        "You do not have permission to configure payment providers.",
        "forbidden"
      )
    end
  end
end
