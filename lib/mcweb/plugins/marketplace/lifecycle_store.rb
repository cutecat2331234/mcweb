# frozen_string_literal: true

require "digest"
require_relative "../manifest"
require_relative "error"

module Mcweb
  module Plugins
    module Marketplace
      class LifecycleStore
        STALE_AFTER = 15.minutes
        ERROR_MESSAGE_LIMIT = 1_000
        ACTION_STATE = {
          "install" => [ "installing", "enabled", "enabled" ],
          "upgrade" => [ "upgrading", "enabled", "enabled" ],
          "enable" => [ "enabling", "enabled", "enabled" ],
          "disable" => [ "disabling", "disabled", "disabled" ],
          "uninstall" => [ "uninstalling", "uninstalled", "uninstalled" ],
          "rollback" => [ "rolling_back", "enabled", "enabled" ],
          "recover" => [ "rolling_back", "enabled", "enabled" ]
        }.freeze

        def initialize(clock: -> { Time.current })
          @clock = clock
        end

        def available?
          ActiveRecord::Base.connection.data_source_exists?("plugin_installations") &&
            ActiveRecord::Base.connection.data_source_exists?("plugin_lifecycle_runs") &&
            ActiveRecord::Base.connection.data_source_exists?("plugin_lifecycle_steps")
        rescue ActiveRecord::ActiveRecordError
          false
        end

        def start!(operation_id:, action:, plugin_id: nil, actor: nil,
                   dry_run: false, maintenance_mode: false)
          return unless available?

          PluginLifecycleRun.transaction do
            run = PluginLifecycleRun.create!(
              operation_id:,
              plugin_id: normalize_optional_plugin_id(plugin_id),
              action: normalize_action(action),
              state: "running",
              actor:,
              dry_run:,
              maintenance_mode:,
              retryable: true,
              started_at: @clock.call
            )
            bind!(run:, plugin_id:) if plugin_id.present?
            run
          end
        end

        def bind!(run:, plugin_id:, from_version: nil, to_version: nil, action: nil)
          return unless run

          plugin_id = normalize_plugin_id(plugin_id)
          if run.dry_run?
            run.update!(
              plugin_id:,
              action: action ? normalize_action(action) : run.action,
              from_version: from_version.to_s.presence,
              to_version: to_version.to_s.presence
            )
            bind_maintenance_window!(run:, plugin_id:)
            return run.reload
          end

          PluginInstallation.transaction do
            installation = PluginInstallation.lock.find_or_initialize_by(plugin_id:)
            reject_concurrent_operation!(installation, operation_id: run.operation_id)
            run_action = action ? normalize_action(action) : run.action
            running_state, desired_state = action_states(run_action).values_at(0, 2)
            installation.assign_attributes(
              desired_state:,
              current_state: running_state,
              last_operation_id: run.operation_id,
              error_code: nil,
              error_message: nil
            )
            installation.save!
            run.update!(
              plugin_installation: installation,
              plugin_id:,
              action: run_action,
              from_version: from_version.to_s.presence || installation.current_version,
              to_version: to_version.to_s.presence
            )
          end
          bind_maintenance_window!(run:, plugin_id:)
          run.reload
        end

        def checkpoint!(run:, step_key:, details: {}, retryable: true)
          return unless run

          now = @clock.call
          sequence = run.steps.maximum(:sequence).to_i
          sequence += 1 if run.steps.exists?
          key = step_key.to_s
          run.steps.create!(
            sequence:,
            step_key: key,
            state: "succeeded",
            idempotency_key: Digest::SHA256.hexdigest(
              "#{run.operation_id}:#{sequence}:#{key}"
            ),
            retryable:,
            details: normalize_details(details),
            started_at: now,
            completed_at: now
          )
        end

        def open_maintenance!(operation_id:, plugin_id: nil, actor: nil)
          return unless maintenance_available?

          PluginMaintenanceWindow.open!(
            operation_id:,
            plugin_id:,
            actor:
          )
        end

        def close_maintenance!(window)
          window&.close!
        rescue ActiveRecord::ActiveRecordError => e
          Rails.logger.error(
            "[mcweb.plugins] maintenance window close failed: #{e.class}"
          )
          nil
        end

        def finish!(run:, succeeded:, plugin_id: nil, version: nil,
                    generation_number: nil, recovery_path: nil, error: nil)
          return unless run

          now = @clock.call
          generation_number ||= generation_number_for(run.operation_id)
          sanitized_error = safe_error(error)
          PluginLifecycleRun.transaction do
            run.lock!
            run.update!(
              plugin_id: normalize_optional_plugin_id(plugin_id) || run.plugin_id,
              state: succeeded ? "succeeded" : "failed",
              to_version: version.to_s.presence || run.to_version,
              generation_number:,
              recovery_path: recovery_path.to_s.presence,
              error_code: succeeded ? nil : error_code(error),
              error_message: succeeded ? nil : sanitized_error,
              completed_at: now
            )
            installation = run.plugin_installation
            next unless installation

            installation.lock!
            _running_state, success_state, desired_state = action_states(run.action)
            installation.assign_attributes(
              desired_state:,
              current_state: succeeded ? success_state : "failed",
              current_version: successful_version(
                installation:,
                run:,
                succeeded:,
                version:
              ),
              active_generation_number: generation_number ||
                installation.active_generation_number,
              last_operation_id: run.operation_id,
              error_code: succeeded ? nil : error_code(error),
              error_message: succeeded ? nil : sanitized_error
            )
            installation.save!
          end
          run.reload
        end

        def recover_stale!(before: @clock.call - STALE_AFTER)
          return [] unless available?

          recovered = []
          PluginLifecycleRun.running.where("started_at < ?", before).find_each do |run|
            PluginLifecycleRun.transaction do
              run.lock!
              next unless run.state == "running" && run.started_at < before

              now = @clock.call
              run.update!(
                state: "interrupted",
                error_code: "lifecycle_interrupted",
                error_message: "lifecycle process ended before completion",
                completed_at: now
              )
              if (installation = run.plugin_installation)
                installation.lock!
                installation.update!(
                  current_state: "failed",
                  error_code: "lifecycle_interrupted",
                  error_message: "lifecycle process ended before completion"
                )
              end
              recovered << run.id
            end
          end
          recovered.freeze
        end

        private

        def action_states(action)
          ACTION_STATE.fetch(normalize_action(action))
        end

        def normalize_action(value)
          action = value.to_s
          return action if ACTION_STATE.key?(action)

          raise LifecycleError, "unsupported plugin lifecycle action"
        end

        def normalize_plugin_id(value)
          id = value.to_s
          unless id.length <= Manifest::MAX_ID_LENGTH && id.match?(Manifest::ID_PATTERN)
            raise LifecycleError, "invalid plugin id"
          end
          id
        end

        def normalize_optional_plugin_id(value)
          value.present? ? normalize_plugin_id(value) : nil
        end

        def reject_concurrent_operation!(installation, operation_id:)
          return unless installation.persisted?
          return unless PluginInstallation::BUSY_STATES.include?(installation.current_state)
          return if installation.last_operation_id == operation_id

          raise LifecycleError,
            "another plugin lifecycle operation is already running"
        end

        def successful_version(installation:, run:, succeeded:, version:)
          return installation.current_version unless succeeded
          return nil if run.action == "uninstall"

          version.to_s.presence || run.to_version || installation.current_version
        end

        def normalize_details(value)
          data = value.respond_to?(:to_h) ? value.to_h : {}
          data.each_with_object({}) do |(raw_key, raw_value), result|
            key = raw_key.to_s.slice(0, 128)
            next if key.blank?

            result[key] =
              case raw_value
              when String, Numeric, TrueClass, FalseClass, NilClass
                raw_value.is_a?(String) ? raw_value.slice(0, 512) : raw_value
              else
                raw_value.to_s.slice(0, 512)
              end
          end
        end

        def error_code(error)
          return "lifecycle_failed" unless error

          error.class.name.to_s.underscore.tr("/", ".").slice(0, 191)
        end

        def safe_error(error)
          return unless error

          "#{error.class}: #{error.message}"
            .gsub(/(token|secret|password|authorization)\s*[=:]\s*\S+/i, "\\1=[REDACTED]")
            .slice(0, ERROR_MESSAGE_LIMIT)
        end

        def generation_number_for(operation_id)
          return unless defined?(PluginGeneration)

          PluginGeneration.where(operation_id:).maximum(:number)
        rescue ActiveRecord::ActiveRecordError
          nil
        end

        def bind_maintenance_window!(run:, plugin_id:)
          return unless maintenance_available?

          PluginMaintenanceWindow
            .where(operation_id: run.operation_id)
            .update_all(plugin_id:, updated_at: @clock.call)
        end

        def maintenance_available?
          defined?(PluginMaintenanceWindow) &&
            ActiveRecord::Base.connection.data_source_exists?(
              "plugin_maintenance_windows"
            )
        rescue ActiveRecord::ActiveRecordError
          false
        end
      end
    end
  end
end
