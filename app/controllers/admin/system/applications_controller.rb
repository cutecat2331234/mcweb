# frozen_string_literal: true

require "mcweb/plugins/marketplace"
require "tempfile"
require "digest"

module Admin
  module System
    class ApplicationsController < BaseController
      MAX_PLUGIN_PACKAGE_BYTES = 50.megabytes
      SHA256_PATTERN = /\A[0-9a-f]{64}\z/
      SAFE_FILENAME_PATTERN = /[^A-Za-z0-9._-]/
      LEGACY_PLUGIN_PERMISSION = "system.plugins.manage"
      PLUGIN_ACTION_PERMISSIONS = {
        install_plugin: "system.plugins.install",
        enable_plugin: "system.plugins.enable",
        disable_plugin: "system.plugins.disable",
        recover_plugin: "system.plugins.recover",
        rollback_plugin: "system.plugins.rollback",
        health_plugin: "system.plugins.diagnostics",
        reconcile_plugin_catalog: "system.plugins.diagnostics"
      }.freeze

      class PluginUploadError < StandardError; end

      class_attribute :marketplace_manager_factory,
                      instance_accessor: false,
                      default: -> { Mcweb::Plugins::Marketplace.manager }

      before_action :require_applications_access, only: :index
      before_action :require_plugin_action_permission,
                    only: PLUGIN_ACTION_PERMISSIONS.keys
      before_action :require_plugin_uninstall_permission, only: :uninstall_plugin

      def index
        catalog = Mcweb::ApplicationRegistry.admin_catalog
        plugins, plugin_diagnostics = plugin_runtime_catalog

        render inertia: "Admin/System/Applications/Index", props: {
          title: t("mcweb.admin.system.applications.title"),
          platform: catalog[:platform],
          applications: catalog[:applications],
          extensions: catalog[:extensions],
          plugins: plugins,
          pluginDiagnostics: can_diagnose_plugins? ? plugin_diagnostics : [],
          pluginMarketplace: plugin_marketplace_snapshot,
          pluginLifecycle: can_diagnose_plugins? ? plugin_lifecycle_snapshot :
            { available: false, installations: [], runs: [] },
          pluginCatalog: can_diagnose_plugins? ? plugin_catalog_snapshot :
            { available: false, releases: [] },
          pluginRuntimeGenerations: can_diagnose_plugins? ?
            plugin_runtime_generation_snapshot :
            { available: false, generations: [] },
          pluginActions: {
            install: install_plugin_admin_system_applications_path,
            enable: enable_plugin_admin_system_applications_path,
            disable: disable_plugin_admin_system_applications_path,
            uninstall: uninstall_plugin_admin_system_applications_path,
            recover: recover_plugin_admin_system_applications_path,
            rollback: rollback_plugin_admin_system_applications_path,
            health: health_plugin_admin_system_applications_path,
            reconcileCatalog: reconcile_plugin_catalog_admin_system_applications_path
          },
          canManagePlugins: plugin_action_capabilities.values.any?,
          pluginCapabilities: plugin_action_capabilities,
          freelyExtensible: Mcweb::ApplicationRegistry.freely_extensible?,
          featureFlagsUrl: admin_system_feature_toggles_path
        }
      end

      def install_plugin
        upload = plugin_upload!
        expected_sha256 = params[:expected_sha256].to_s
        unless expected_sha256.match?(SHA256_PATTERN)
          raise PluginUploadError, t("mcweb.admin.system.applications.marketplace.invalid_sha256")
        end

        result = with_staged_plugin_upload(upload) do |package_path, source|
          marketplace_manager.install(
            package_path: package_path,
            source: source,
            expected_sha256: expected_sha256,
            expected_id: params[:expected_id].presence,
            allow_downgrade: ActiveModel::Type::Boolean.new.cast(params[:allow_downgrade]),
            actor: current_user,
            dry_run: lifecycle_option?(:dry_run),
            maintenance_mode: lifecycle_option?(:maintenance_mode)
          )
        end
        redirect_after_marketplace_operation(result)
      rescue PluginUploadError, Mcweb::Plugins::Marketplace::Error => e
        redirect_marketplace_error(e)
      rescue StandardError => e
        log_marketplace_failure("install", e)
        redirect_marketplace_error
      end

      def enable_plugin
        perform_marketplace_operation(:enable)
      end

      def disable_plugin
        perform_marketplace_operation(:disable)
      end

      def recover_plugin
        perform_marketplace_operation(
          :recover,
          expected_version: params[:expected_version].to_s,
          expected_sha256: params[:expected_sha256].to_s
        )
      end

      def rollback_plugin
        perform_marketplace_operation(
          :rollback,
          expected_version: params[:expected_version].to_s,
          expected_sha256: params[:expected_sha256].to_s
        )
      end

      def uninstall_plugin
        plugin_id = params[:plugin_id].to_s
        unless params[:confirmation].to_s == plugin_id
          redirect_to(
            admin_system_applications_path,
            alert: t(
              "mcweb.admin.system.applications.marketplace.uninstall_confirmation_mismatch"
            )
          )
          return
        end

        perform_marketplace_operation(
          :uninstall,
          expected_version: params[:expected_version].to_s,
          expected_sha256: params[:expected_sha256].to_s,
          data_mode: params[:data_mode].to_s.presence || "preserve_data"
        )
      end

      def health_plugin
        result = marketplace_manager.health(plugin_id: params[:plugin_id].to_s)
        redirect_to(
          admin_system_applications_path,
          notice: t(
            "mcweb.admin.system.applications.marketplace.health_completed",
            plugin: result.fetch(:plugin_id),
            status: t(
              "mcweb.admin.system.applications.marketplace.health_status.#{result.fetch(:status)}"
            )
          )
        )
      rescue Mcweb::Plugins::Marketplace::Error => e
        redirect_marketplace_error(e)
      rescue StandardError => e
        log_marketplace_failure("health", e)
        redirect_marketplace_error
      end

      def reconcile_plugin_catalog
        result = marketplace_manager.reconcile_catalog
        Administration::AuditLogger.call(
          actor: current_user,
          action: "admin.plugin_catalog_reconciled",
          metadata: {
            scanned_count: result.scanned_count,
            synchronized_count: result.synchronized_count,
            unavailable_count: result.unavailable_count,
            finding_count: result.finding_count,
            finding_codes: result.findings.pluck(:code).uniq.sort.first(50)
          },
          ip_address: request.remote_ip,
          user_agent: request.user_agent,
          request_id: request.request_id
        )
        redirect_to(
          admin_system_applications_path,
          notice: t(
            "mcweb.admin.system.applications.marketplace.catalog_reconciled",
            plugins: result.synchronized_count,
            findings: result.finding_count
          )
        )
      rescue Mcweb::Plugins::Marketplace::Error => e
        redirect_marketplace_error(e)
      rescue StandardError => e
        log_marketplace_failure("catalog_reconcile", e)
        redirect_marketplace_error
      end

      private

      def require_applications_access
        return if current_user&.permission?("system.settings.manage")
        return if plugin_permission?("system.plugins.view")
        return if plugin_permission?("system.plugins.diagnostics")

        redirect_to root_path, alert: t("mcweb.flash.permission_denied")
      end

      def require_plugin_action_permission
        permission = PLUGIN_ACTION_PERMISSIONS.fetch(action_name.to_sym)
        return if plugin_permission?(permission)

        redirect_to root_path, alert: t("mcweb.flash.permission_denied")
      end

      def require_plugin_uninstall_permission
        permission =
          if params[:data_mode].to_s == "purge_data"
            "system.plugins.uninstall_purge"
          else
            "system.plugins.uninstall_preserve"
          end
        return if plugin_permission?(permission)

        redirect_to root_path, alert: t("mcweb.flash.permission_denied")
      end

      def plugin_permission?(permission)
        current_user&.permission?(permission) ||
          current_user&.permission?(LEGACY_PLUGIN_PERMISSION)
      end

      def can_diagnose_plugins?
        plugin_permission?("system.plugins.diagnostics")
      end

      def plugin_action_capabilities
        {
          install: plugin_permission?("system.plugins.install"),
          enable: plugin_permission?("system.plugins.enable"),
          disable: plugin_permission?("system.plugins.disable"),
          diagnostics: can_diagnose_plugins?,
          recover: plugin_permission?("system.plugins.recover"),
          rollback: plugin_permission?("system.plugins.rollback"),
          uninstall_preserve: plugin_permission?("system.plugins.uninstall_preserve"),
          uninstall_purge: plugin_permission?("system.plugins.uninstall_purge")
        }
      end

      def marketplace_manager
        self.class.marketplace_manager_factory.call
      end

      def plugin_marketplace_snapshot
        snapshot = marketplace_manager.status(recent_operations: 50)
        {
          available: true,
          plugins: Array(snapshot[:plugins]).map { |entry| serialize_marketplace_plugin(entry) },
          errors: Array(snapshot[:errors]).map { |entry| serialize_marketplace_error(entry) },
          operations: Array(snapshot[:operations]).map { |entry| serialize_marketplace_operation(entry) }
        }
      rescue StandardError => e
        log_marketplace_failure("status", e)
        {
          available: false,
          plugins: [],
          operations: [],
          errors: [
            {
              code: "marketplace_unavailable",
              message: t("mcweb.admin.system.applications.marketplace.unavailable")
            }
          ]
        }
      end

      def plugin_runtime_generation_snapshot
        return { available: false, generations: [] } unless
          ActiveRecord::Base.connection.data_source_exists?("plugin_generations")

        generations = PluginGeneration.includes(:process_acks).ordered.limit(20).map do |generation|
          {
            number: generation.number,
            state: generation.state,
            action: generation.action,
            target_plugin_id: generation.target_plugin_id,
            desired_plugins: generation.desired_plugins,
            minimum_ack_ratio: generation.minimum_ack_ratio.to_f,
            expected_process_count: Array(generation.expected_process_uids).length,
            deadline_at: generation.deadline_at&.iso8601,
            activated_at: generation.activated_at&.iso8601,
            error_code: generation.error_code,
            error_message: safe_marketplace_message(generation.error_message),
            acknowledgements: generation.process_acks.sort_by(&:process_uid).map do |ack|
              {
                process_ref: Digest::SHA256.hexdigest(ack.process_uid)[0, 12],
                process_kind: ack.process_kind,
                status: ack.status,
                plugin_versions: ack.plugin_versions,
                error_code: ack.error_code,
                error_message: safe_marketplace_message(ack.error_message),
                acked_at: ack.acked_at&.iso8601,
                last_seen_at: ack.last_seen_at&.iso8601
              }
            end
          }
        end

        { available: true, generations: }
      rescue StandardError => e
        log_marketplace_failure("generation_status", e)
        { available: false, generations: [] }
      end

      def plugin_lifecycle_snapshot
        return { available: false, installations: [], runs: [] } unless
          ActiveRecord::Base.connection.data_source_exists?("plugin_lifecycle_runs")

        installations = PluginInstallation.order(:plugin_id).map do |installation|
          {
            plugin_id: installation.plugin_id,
            current_version: installation.current_version,
            desired_state: installation.desired_state,
            current_state: installation.current_state,
            active_generation_number: installation.active_generation_number,
            last_operation_id: installation.last_operation_id,
            error_code: installation.error_code,
            error_message: safe_marketplace_message(installation.error_message),
            updated_at: installation.updated_at&.iso8601
          }
        end
        runs = PluginLifecycleRun.includes(:actor, :steps).recent_first.limit(50).map do |run|
          {
            operation_id: run.operation_id,
            plugin_id: run.plugin_id,
            action: run.action,
            state: run.state,
            actor: run.actor&.username,
            from_version: run.from_version,
            to_version: run.to_version,
            generation_number: run.generation_number,
            dry_run: run.dry_run?,
            maintenance_mode: run.maintenance_mode?,
            retryable: run.retryable,
            error_code: run.error_code,
            error_message: safe_marketplace_message(run.error_message),
            recovery_path: run.recovery_path.present?,
            started_at: run.started_at&.iso8601,
            completed_at: run.completed_at&.iso8601,
            steps: run.steps.map do |step|
              {
                sequence: step.sequence,
                step_key: step.step_key,
                state: step.state,
                retryable: step.retryable,
                error_code: step.error_code,
                error_message: safe_marketplace_message(step.error_message),
                started_at: step.started_at&.iso8601,
                completed_at: step.completed_at&.iso8601
              }
            end
          }
        end
        { available: true, installations:, runs: }
      rescue StandardError => e
        log_marketplace_failure("lifecycle_status", e)
        { available: false, installations: [], runs: [] }
      end

      def plugin_catalog_snapshot
        required = %w[plugin_releases plugin_contributions plugin_files]
        unless required.all? do |table|
          ActiveRecord::Base.connection.data_source_exists?(table)
        end
          return { available: false, releases: [] }
        end

        releases = PluginRelease
          .includes(:contributions, :files)
          .ordered
          .limit(250)
          .map do |release|
            files = release.files.sort_by(&:path)
            {
              id: release.id,
              plugin_id: release.plugin_id,
              version: release.version,
              api_version: release.api_version,
              state: release.state,
              health: release.health,
              manifest_sha256: release.manifest_sha256,
              package_sha256: release.package_sha256,
              package_digest_source: release.package_digest_source,
              operation_id: release.operation_id,
              observed_at: release.observed_at&.iso8601,
              manifest: {
                name: release.manifest_descriptor["name"],
                capabilities: Array(
                  release.manifest_descriptor["capabilities"]
                ).map(&:to_s)
              },
              diagnostics: Array(release.diagnostics).filter_map do |entry|
                serialize_catalog_diagnostic(entry)
              end,
              contributions: release.contributions.sort_by(&:contribution_id).map do |entry|
                {
                  id: entry.contribution_id,
                  type: entry.contribution_type,
                  descriptor_sha256: entry.descriptor_sha256,
                  schema_sha256: entry.schema_sha256
                }
              end,
              file_count: files.length,
              file_health_counts: files.group_by(&:health).transform_values(&:length),
              file_issues: files.reject { |entry| entry.health == "healthy" }.first(200).map do |entry|
                {
                  path: entry.path,
                  health: entry.health,
                  expected_size: entry.byte_size,
                  observed_size: entry.observed_byte_size,
                  sha256: entry.sha256,
                  observed_sha256: entry.observed_sha256
                }
              end
            }
          end
        { available: true, releases: }
      rescue StandardError => e
        log_marketplace_failure("catalog_status", e)
        { available: false, releases: [] }
      end

      def serialize_catalog_diagnostic(entry)
        data = entry.respond_to?(:to_h) ? entry.to_h : {}
        code = (data["code"] || data[:code]).to_s
        return if code.blank?

        {
          code: code.slice(0, 128),
          severity: (data["severity"] || data[:severity]).to_s == "error" ?
            "error" : "warning"
        }
      end

      def plugin_upload!
        upload = params[:plugin_package]
        unless upload.respond_to?(:tempfile) && upload.respond_to?(:original_filename)
          raise PluginUploadError, t("mcweb.admin.system.applications.marketplace.package_required")
        end

        filename = File.basename(upload.original_filename.to_s)
        unless File.extname(filename).casecmp?(".zip")
          raise PluginUploadError, t("mcweb.admin.system.applications.marketplace.zip_required")
        end

        upload
      end

      def with_staged_plugin_upload(upload)
        input = upload.tempfile
        input.binmode
        input.rewind
        filename = safe_plugin_filename(upload.original_filename)

        Tempfile.create([ "mcweb-plugin-upload-", ".zip" ]) do |temporary|
          temporary.binmode
          copied = 0
          while (chunk = input.read(64.kilobytes))
            copied += chunk.bytesize
            if copied > MAX_PLUGIN_PACKAGE_BYTES
              raise PluginUploadError, t("mcweb.admin.system.applications.marketplace.package_too_large")
            end
            temporary.write(chunk)
          end
          raise PluginUploadError, t("mcweb.admin.system.applications.marketplace.package_empty") if copied.zero?

          temporary.flush
          temporary.fsync
          yield temporary.path, "file:///admin-upload/#{filename}"
        end
      ensure
        input&.rewind
      end

      def safe_plugin_filename(original_filename)
        filename = File.basename(original_filename.to_s)
          .gsub(SAFE_FILENAME_PATTERN, "_")
          .slice(0, 128)
        filename.presence || "plugin.zip"
      end

      def perform_marketplace_operation(action, **attributes)
        result = marketplace_manager.public_send(
          action,
          plugin_id: params[:plugin_id].to_s,
          actor: current_user,
          dry_run: lifecycle_option?(:dry_run),
          maintenance_mode: lifecycle_option?(:maintenance_mode),
          **attributes
        )
        redirect_after_marketplace_operation(result)
      rescue Mcweb::Plugins::Marketplace::Error => e
        redirect_marketplace_error(e)
      rescue StandardError => e
        log_marketplace_failure(action, e)
        redirect_marketplace_error
      end

      def redirect_after_marketplace_operation(result)
        translation_key =
          if result.status.to_s == "validated"
            "mcweb.admin.system.applications.marketplace.dry_run_succeeded"
          else
            "mcweb.admin.system.applications.marketplace.operation_succeeded"
          end
        redirect_to(
          admin_system_applications_path,
          notice: t(
            translation_key,
            action: result.action.to_s,
            plugin: result.plugin_id.to_s
          )
        )
      end

      def lifecycle_option?(key)
        ActiveModel::Type::Boolean.new.cast(params[key]) == true
      end

      def redirect_marketplace_error(error = nil)
        redirect_to(
          admin_system_applications_path,
          alert: error ? safe_marketplace_message(error.message) :
            t("mcweb.admin.system.applications.marketplace.operation_failed")
        )
      end

      def serialize_marketplace_plugin(entry)
        source = marketplace_value(entry, :source)
        source = source.respond_to?(:to_h) ? source.to_h : {}
        {
          id: marketplace_value(entry, :id).to_s,
          name: marketplace_value(entry, :name).to_s.presence || marketplace_value(entry, :id).to_s,
          version: marketplace_value(entry, :version).to_s,
          api_version: marketplace_value(entry, :api_version).to_s,
          status: marketplace_value(entry, :status).to_s,
          filesystem_status: marketplace_value(entry, :filesystem_status).to_s,
          runtime_status: marketplace_value(entry, :runtime_status).to_s.presence,
          source: {
            scheme: marketplace_value(source, :scheme).to_s.presence,
            host: marketplace_value(source, :host).to_s.presence
          }.compact,
          sha256: marketplace_value(entry, :sha256).to_s.presence,
          updated_at: marketplace_value(entry, :updated_at).to_s.presence,
          recoverable: marketplace_value(entry, :recovery_path).present?,
          rollback_available: marketplace_value(entry, :rollback_available) == true,
          data_mode: marketplace_value(entry, :data_mode).to_s.presence,
          health: serialize_plugin_health(marketplace_value(entry, :health))
        }
      end

      def serialize_plugin_health(entry)
        data = entry.respond_to?(:to_h) ? entry.to_h : {}
        {
          status: marketplace_value(data, :status).to_s.presence || "unavailable",
          expected_count: marketplace_value(data, :expected_count).to_i,
          actual_count: marketplace_value(data, :actual_count).to_i,
          missing_count: Array(marketplace_value(data, :missing)).length,
          modified_count: Array(marketplace_value(data, :modified)).length,
          unknown_count: Array(marketplace_value(data, :unknown)).length
        }
      end

      def serialize_marketplace_error(entry)
        {
          code: marketplace_value(entry, :code).to_s.presence || "marketplace_error",
          message: safe_marketplace_message(marketplace_value(entry, :message))
        }
      end

      def serialize_marketplace_operation(entry)
        {
          operation_id: marketplace_value(entry, :operation_id).to_s,
          action: marketplace_value(entry, :action).to_s,
          status: marketplace_value(entry, :status).to_s,
          plugin_id: marketplace_value(entry, :plugin_id).to_s.presence,
          version: marketplace_value(entry, :version).to_s.presence,
          message: safe_marketplace_message(marketplace_value(entry, :message)),
          occurred_at: marketplace_value(entry, :occurred_at).to_s.presence,
          recoverable: marketplace_value(entry, :recovery_path).present?
        }
      end

      def marketplace_value(entry, key)
        return unless entry.respond_to?(:to_h)

        data = entry.to_h
        data[key] || data[key.to_s]
      end

      def safe_marketplace_message(message)
        value = message.to_s.encode(
          Encoding::UTF_8,
          invalid: :replace,
          undef: :replace,
          replace: "?"
        )
        value = value.gsub(/[[:cntrl:]]+/, " ")
        value = value.gsub(
          /((?:access_?token|api_?key|secret|password|signature)\s*[=:]\s*)[^\s&]+/i,
          '\1[redacted]'
        )
        value = value.gsub(
          %r{(?<![A-Za-z0-9._-])(?:[A-Za-z]:[\\/]|/)(?:[^,\s;:]+[\\/]?)+},
          "[redacted-path]"
        )
        value.presence&.slice(0, 512) ||
          t("mcweb.admin.system.applications.marketplace.operation_failed")
      end

      def log_marketplace_failure(action, error)
        Rails.logger.warn(
          "[admin.plugin_marketplace] #{action} failed: #{error.class.name}"
        )
      end

      def plugin_runtime_catalog
        unless defined?(Mcweb::Plugins) &&
            Mcweb::Plugins.respond_to?(:list) &&
            Mcweb::Plugins.respond_to?(:diagnostics)
          return [ [], [ plugin_catalog_diagnostic("plugin_sdk_unavailable", "Plugin SDK status is unavailable.") ] ]
        end

        plugins = Array(Mcweb::Plugins.list).filter_map { |entry| serialize_plugin(entry) }
        diagnostics = Array(Mcweb::Plugins.diagnostics).filter_map { |entry| serialize_plugin_diagnostic(entry) }
        [ plugins, diagnostics ]
      rescue StandardError => e
        Rails.logger.warn("[admin.applications] unable to read plugin catalog: #{e.class.name}")
        [ [], [ plugin_catalog_diagnostic(
          "plugin_catalog_failed",
          safe_marketplace_message(e.message),
          exception: e.class.name
        ) ] ]
      end

      def serialize_plugin(entry)
        data = entry.respond_to?(:to_h) ? entry.to_h.deep_symbolize_keys : {}
        return if data[:id].blank?

        {
          id: data[:id].to_s,
          name: data[:name].to_s.presence || data[:id].to_s,
          version: data[:version].to_s,
          api_version: data[:api_version].to_s,
          description: data[:description].to_s.presence,
          author: data[:author].to_s.presence,
          homepage: data[:homepage].to_s.presence,
          requires: normalize_string_hash(data[:requires]),
          capabilities: Array(data[:capabilities]).map(&:to_s),
          status: data[:status].to_s.presence || "registered",
          listener_count: data[:listener_count].to_i,
          contribution_count: data[:contribution_count].to_i,
          contribution_descriptors: Array(data[:contribution_descriptors]).filter_map do |descriptor|
            serialize_contribution_descriptor(descriptor)
          end,
          failure_count: data[:failure_count].to_i,
          last_error: data[:last_error].present? ? safe_marketplace_message(data[:last_error]) : nil,
          activation_order: data[:activation_order]
        }
      end

      def serialize_contribution_descriptor(entry)
        data = entry.respond_to?(:to_h) ? entry.to_h.deep_symbolize_keys : {}
        return if data[:id].blank? || data[:type].blank?

        {
          id: data[:id].to_s,
          type: data[:type].to_s,
          priority: data[:priority].to_i,
          before: Array(data[:before]).map(&:to_s),
          after: Array(data[:after]).map(&:to_s),
          requires: Array(data[:requires]).map(&:to_s),
          conflicts: Array(data[:conflicts]).map(&:to_s),
          payload: Mcweb::PluginApi::V1::Normalizer.call(data[:payload] || {})
        }
      rescue StandardError
        nil
      end

      def serialize_plugin_diagnostic(entry)
        data = entry.respond_to?(:to_h) ? entry.to_h.deep_symbolize_keys : {}
        return if data.empty?

        {
          level: data[:level].to_s.presence || "warning",
          code: data[:code].to_s.presence || "unknown",
          phase: data[:phase].to_s.presence || "runtime",
          plugin_id: data[:plugin_id].to_s.presence,
          event: data[:event].to_s.presence,
          message: safe_marketplace_message(data[:message]),
          exception: data[:exception].to_s.presence,
          occurred_at: data[:occurred_at].to_s.presence
        }
      end

      def normalize_string_hash(value)
        return {} unless value.respond_to?(:to_h)

        value.to_h.each_with_object({}) do |(key, requirement), result|
          result[key.to_s] = requirement.to_s
        end
      end

      def plugin_catalog_diagnostic(code, message, exception: nil)
        {
          level: "warning",
          code: code,
          phase: "catalog",
          message: message.to_s,
          exception: exception
        }.compact
      end
    end
  end
end
