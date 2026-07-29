# frozen_string_literal: true

require "test_helper"

class PluginMaintenanceWindowTest < ActionDispatch::IntegrationTest
  teardown do
    PluginMaintenanceWindow.delete_all
    PluginMaintenanceWindow.clear_active_cache!
  end

  test "active plugin maintenance window pauses public html and json requests" do
    open_window

    get root_path
    assert_response :service_unavailable
    assert_includes response.body, I18n.t("mcweb.plugin_maintenance.title")
    assert_equal "30", response.headers["Retry-After"]

    get root_path, as: :json
    assert_response :service_unavailable
    payload = JSON.parse(response.body)
    assert_equal "plugin_maintenance", payload.fetch("error")
    assert_equal I18n.t("mcweb.plugin_maintenance.message"),
                 payload.fetch("message")
  end

  test "administrators and expired windows do not block public controllers" do
    expired = PluginMaintenanceWindow.create!(
      operation_id: SecureRandom.uuid,
      active: true,
      started_at: 2.hours.ago,
      expires_at: 1.hour.ago
    )
    PluginMaintenanceWindow.clear_active_cache!

    get root_path
    refute_equal 503, response.status

    expired.update!(
      started_at: Time.current,
      expires_at: 5.minutes.from_now
    )
    PluginMaintenanceWindow.clear_active_cache!
    admin = create_user
    grant_permission(admin, "admin.access")
    sign_in_as(admin)

    get root_path
    refute_equal 503, response.status
  end

  private

  def open_window
    PluginMaintenanceWindow.open!(
      operation_id: SecureRandom.uuid,
      duration: 5.minutes
    )
  end
end
