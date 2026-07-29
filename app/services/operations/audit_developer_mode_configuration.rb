# frozen_string_literal: true

require "digest"
require "json"

module Operations
  class AuditDeveloperModeConfiguration
    SINGLETON_ID = 1

    class << self
      def call(settings: Mcweb::DeveloperMode.settings, now: Time.current)
        summary = configuration_summary(settings)
        digest = Digest::SHA256.hexdigest(JSON.generate(summary))
        return true if @persisted_digest == digest

        persist!(summary:, digest:, now:)
        @persisted_digest = digest
        true
      rescue ActiveRecord::ActiveRecordError => error
        Rails.logger.warn(
          "[DeveloperMode] configuration audit deferred: #{error.class}"
        )
        false
      end

      def reset_process_cache!
        @persisted_digest = nil
      end

      private

      def persist!(summary:, digest:, now:)
        DeveloperModeRuntimeState.transaction do
          state = DeveloperModeRuntimeState.lock.find_or_initialize_by(
            id: SINGLETON_ID
          )
          return if state.persisted? &&
            state.configuration_digest == digest

          before_state =
            state.persisted? ? state.configuration_summary : {}

          AuditLog.record!(
            action: "system.developer_mode_configuration_changed",
            metadata: {
              source: "runtime_observation",
              configuration_digest: digest
            },
            before_state: before_state,
            after_state: summary
          )

          state.assign_attributes(
            enabled: summary.fetch(:enabled),
            profile: summary.fetch(:profile),
            configuration_digest: digest,
            configuration_summary: summary,
            observed_at: now
          )
          state.save!
        end
      end

      def configuration_summary(settings)
        {
          enabled: settings.enabled?,
          profile: settings.profile.to_s,
          auto_login_configured: settings.auto_login_user.present?,
          security: normalized_group(settings.security),
          integrations: normalized_group(settings.integrations),
          runtime: normalized_group(settings.runtime)
        }
      end

      def normalized_group(values)
        values.to_h
          .sort_by { |key, _value| key.to_s }
          .to_h do |key, value|
            [ key.to_s, value.nil? ? nil : value.to_s ]
          end
      end
    end
  end
end
