# frozen_string_literal: true

require "mcweb/plugins/marketplace"
require "tempfile"

module Admin
  module System
    class ApplicationsController < BaseController
      MAX_PLUGIN_PACKAGE_BYTES = 50.megabytes
      SHA256_PATTERN = /\A[0-9a-f]{64}\z/
      SAFE_FILENAME_PATTERN = /[^A-Za-z0-9._-]/

      class PluginUploadError < StandardError; end

      class_attribute :marketplace_manager_factory,
                      instance_accessor: false,
                      default: -> { Mcweb::Plugins::Marketplace.manager }

      before_action :require_applications_access, only: :index
      before_action -> { require_permission("system.plugins.manage") }, except: :index

      def index
        catalog = Mcweb::ApplicationRegistry.admin_catalog
        plugins, plugin_diagnostics = plugin_runtime_catalog

        render inertia: "Admin/System/Applications/Index", props: {
          title: t("mcweb.admin.system.applications.title"),
          platform: catalog[:platform],
          applications: catalog[:applications],
          extensions: catalog[:extensions],
          plugins: plugins,
          pluginDiagnostics: plugin_diagnostics,
          pluginMarketplace: plugin_marketplace_snapshot,
          pluginActions: {
            install: install_plugin_admin_system_applications_path,
            enable: enable_plugin_admin_system_applications_path,
            disable: disable_plugin_admin_system_applications_path,
            uninstall: uninstall_plugin_admin_system_applications_path
          },
          canManagePlugins: current_user.permission?("system.plugins.manage"),
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
            allow_downgrade: ActiveModel::Type::Boolean.new.cast(params[:allow_downgrade])
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
          expected_sha256: params[:expected_sha256].to_s
        )
      end

      private

      def require_applications_access
        return if current_user&.permission?("system.settings.manage")
        return if current_user&.permission?("system.plugins.manage")

        redirect_to root_path, alert: t("mcweb.flash.permission_denied")
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
        redirect_to(
          admin_system_applications_path,
          notice: t(
            "mcweb.admin.system.applications.marketplace.operation_succeeded",
            action: result.action.to_s,
            plugin: result.plugin_id.to_s
          )
        )
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
          recoverable: marketplace_value(entry, :recovery_path).present?
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
          failure_count: data[:failure_count].to_i,
          last_error: data[:last_error].present? ? safe_marketplace_message(data[:last_error]) : nil,
          activation_order: data[:activation_order]
        }
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
