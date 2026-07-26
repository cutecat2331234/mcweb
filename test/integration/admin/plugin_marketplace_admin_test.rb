# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"
require "ostruct"
require "tempfile"

module Admin
  class PluginMarketplaceAdminTest < ActionDispatch::IntegrationTest
    class FakeManager
      attr_reader :calls, :staged_path
      attr_accessor :error_for

      def initialize
        @calls = []
      end

      def status(recent_operations:)
        calls << [ :status, recent_operations ]
        {
          plugins: [
            {
              id: "acme/demo",
              name: "Demo",
              version: "1.0.0",
              api_version: "1",
              status: "active",
              filesystem_status: "installed",
              runtime_status: "active",
              source: { scheme: "file", url: "file:///admin-upload/demo.zip" },
              sha256: "a" * 64,
              recovery_path: "quarantine/private/location",
              updated_at: "2026-07-25T00:00:00Z"
            }
          ],
          errors: [],
          operations: [
            {
              operation_id: "operation-1",
              action: "install",
              status: "succeeded",
              plugin_id: "acme/demo",
              version: "1.0.0",
              occurred_at: "2026-07-25T00:00:00Z",
              recovery_path: "backups/private/location"
            }
          ]
        }
      end

      def install(**attributes)
        raise error_for if error_for

        @staged_path = attributes.fetch(:package_path)
        calls << [ :install, attributes.except(:package_path).merge(
          package_bytes: File.binread(staged_path),
          staged_exists: File.file?(staged_path)
        ) ]
        result("install", "active")
      end

      def enable(plugin_id:)
        lifecycle(:enable, plugin_id, "active")
      end

      def disable(plugin_id:)
        lifecycle(:disable, plugin_id, "disabled")
      end

      def uninstall(plugin_id:, expected_version:, expected_sha256:)
        raise error_for if error_for

        calls << [ :uninstall, plugin_id, expected_version, expected_sha256 ]
        result("uninstall", "uninstalled", plugin_id:)
      end

      private

      def lifecycle(action, plugin_id, status)
        raise error_for if error_for

        calls << [ action, plugin_id ]
        result(action.to_s, status, plugin_id:)
      end

      def result(action, status, plugin_id: "acme/demo")
        OpenStruct.new(action:, status:, plugin_id:, version: "1.0.0")
      end
    end

    setup do
      @admin = create_user
      grant_permission(@admin, "admin.access")
      grant_permission(@admin, "system.settings.manage")
      grant_permission(@admin, "system.plugins.manage")
      grant_admin_module(@admin, "system")
      sign_in_as(@admin)

      @manager = FakeManager.new
      Admin::System::ApplicationsController.marketplace_manager_factory =
        -> { @manager }

      @package = Tempfile.new([ "reviewed-plugin-", ".zip" ])
      @package.binmode
      @package.write("PK\x03\x04reviewed")
      @package.flush
    end

    teardown do
      Admin::System::ApplicationsController.marketplace_manager_factory =
        -> { Mcweb::Plugins::Marketplace.manager }
      @package.close!
    end

    test "index exposes redacted package status operations and action URLs" do
      get admin_system_applications_path

      assert_response :success
      props = inertia.props.deep_symbolize_keys
      assert props[:canManagePlugins]
      assert props[:pluginMarketplace][:available]
      assert_equal "acme/demo", props[:pluginMarketplace][:plugins].sole[:id]
      assert props[:pluginMarketplace][:plugins].sole[:recoverable]
      refute props[:pluginMarketplace][:plugins].sole.key?(:recovery_path)
      refute props[:pluginMarketplace][:plugins].sole.dig(:source)&.key?(:url)
      assert_equal "operation-1", props[:pluginMarketplace][:operations].sole[:operation_id]
      refute props[:pluginMarketplace][:operations].sole.key?(:recovery_path)
      assert_equal install_plugin_admin_system_applications_path, props[:pluginActions][:install]
    end

    test "plugin managers can open applications without the broader settings permission" do
      settings_permission = Permission.find_by!(key: "system.settings.manage")
      @admin.roles
        .joins(:permissions)
        .where(permissions: { id: settings_permission.id })
        .each { |role| @admin.roles.delete(role) }

      get admin_system_applications_path

      assert_response :success
      assert inertia.props.deep_symbolize_keys[:canManagePlugins]
    end

    test "install stages the uploaded ZIP and requires a strict checksum" do
      post install_plugin_admin_system_applications_path, params: {
        plugin_package: uploaded_package,
        expected_sha256: "a" * 64,
        expected_id: "acme/demo",
        allow_downgrade: "0",
        package_path: "C:/operator/secret.zip"
      }

      assert_redirected_to admin_system_applications_path
      call = @manager.calls.find { |entry| entry.first == :install }.second
      assert_equal "PK\x03\x04reviewed", call[:package_bytes]
      assert call[:staged_exists]
      assert_equal "file:///admin-upload/demo.zip", call[:source]
      assert_equal "a" * 64, call[:expected_sha256]
      assert_equal "acme/demo", call[:expected_id]
      assert_equal false, call[:allow_downgrade]
      refute_equal "C:/operator/secret.zip", @manager.staged_path
      refute File.exist?(@manager.staged_path)

      @manager.calls.clear
      post install_plugin_admin_system_applications_path, params: {
        plugin_package: uploaded_package,
        expected_sha256: "A" * 64
      }
      assert_redirected_to admin_system_applications_path
      refute @manager.calls.any? { |entry| entry.first == :install }
    end

    test "enable disable and uninstall call only manager lifecycle APIs" do
      post enable_plugin_admin_system_applications_path, params: { plugin_id: "acme/demo" }
      post disable_plugin_admin_system_applications_path, params: { plugin_id: "acme/demo" }
      delete uninstall_plugin_admin_system_applications_path, params: {
        plugin_id: "acme/demo",
        confirmation: "acme/demo",
        expected_version: "1.0.0",
        expected_sha256: "a" * 64
      }

      assert_includes @manager.calls, [ :enable, "acme/demo" ]
      assert_includes @manager.calls, [ :disable, "acme/demo" ]
      assert_includes @manager.calls, [ :uninstall, "acme/demo", "1.0.0", "a" * 64 ]
    end

    test "uninstall requires the exact plugin id confirmation" do
      delete uninstall_plugin_admin_system_applications_path, params: {
        plugin_id: "acme/demo",
        confirmation: "acme/other"
      }

      assert_redirected_to admin_system_applications_path
      refute @manager.calls.any? { |entry| entry.first == :uninstall }
      assert flash[:alert].present?
    end

    test "plugin management permission is required for mutations" do
      plugin_permission = Permission.find_by!(key: "system.plugins.manage")
      @admin.roles
        .joins(:permissions)
        .where(permissions: { id: plugin_permission.id })
        .each { |role| @admin.roles.delete(role) }

      post disable_plugin_admin_system_applications_path, params: { plugin_id: "acme/demo" }

      assert_redirected_to root_path
      refute @manager.calls.any? { |entry| entry.first == :disable }
    end

    test "manager errors remain readable without leaking paths or secrets" do
      @manager.error_for = Mcweb::Plugins::Marketplace::DependencyError.new(
        "plugin acme/demo is required; C:\\private\\plugins\\demo access_token=never-show"
      )

      post disable_plugin_admin_system_applications_path, params: { plugin_id: "acme/demo" }

      assert_redirected_to admin_system_applications_path
      assert_includes flash[:alert], "acme/demo"
      refute_includes flash[:alert], "C:\\private"
      refute_includes flash[:alert], "never-show"
    end

    private

    def uploaded_package
      @package.rewind
      Rack::Test::UploadedFile.new(
        @package.path,
        "application/zip",
        true,
        original_filename: "demo.zip"
      )
    end
  end
end
