# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  class AuditLogsAdminTest < ActionDispatch::IntegrationTest
    setup do
      @owner = create_user(account_type: "owner", username: "audit_owner")
      @target = create_user(username: "audit_subject")
      @log = AuditLog.record!(
        actor: @owner,
        action: "identity.email_changed",
        resource: @target,
        request_id: "req-audit-123",
        reason: "Verified member request",
        metadata: { channel: "self_service" },
        before_state: { email_verified: true },
        after_state: { email_verified: false }
      )
      sign_in_as(@owner)
    end

    test "index exposes server-filtered paginated rows without raw generic labels" do
      get admin_audit_logs_path, params: {
        event_action: "identity",
        actor: @owner.username,
        resource: @target.public_id,
        request_id: "req-audit-123"
      }

      assert_response :success
      props = inertia.props.deep_symbolize_keys
      assert_equal 1, props.dig(:pagination, :total)
      assert_equal @log.id, props.fetch(:rows).first.fetch(:id)
      assert_equal "req-audit-123", props.fetch(:rows).first.fetch(:requestId)
      assert_equal @target.public_id, props.fetch(:rows).first.dig(:resource, :publicId)
      assert props.fetch(:canExport)
      assert_equal export_admin_audit_logs_path, props.fetch(:exportUrl)
    end

    test "detail exposes immutable state and recorded context" do
      get admin_audit_log_path(@log)

      assert_response :success
      detail = inertia.props.deep_symbolize_keys.fetch(:log)
      assert_equal({ email_verified: true }, detail.fetch(:beforeState))
      assert_equal({ email_verified: false }, detail.fetch(:afterState))
      assert_equal({ channel: "self_service" }, detail.fetch(:metadata))
      assert_equal "Verified member request", detail.fetch(:reason)
    end

    test "separate export permission is enforced" do
      delete identity_session_path
      reader = create_user(account_type: "staff")
      grant_permission(reader, "admin.access")
      grant_permission(reader, "system.audit.read")
      grant_admin_module(reader, "system")
      sign_in_as(reader)

      get export_admin_audit_logs_path(format: :csv)

      assert_redirected_to root_path
    end

    test "filtered CSV is downloaded without caching and the export is audited" do
      assert_difference -> { AuditLog.where(action: "system.audit.exported").count }, 1 do
        get export_admin_audit_logs_path, params: {
          event_action: "identity",
          request_id: "req-audit-123"
        }
      end

      assert_response :success
      assert_includes response.media_type, "text/csv"
      assert_includes response.headers.fetch("Cache-Control"), "private"
      assert_includes response.headers.fetch("Cache-Control"), "no-store"
      assert response.body.start_with?("\uFEFF")
      assert_includes response.body, "req-audit-123"
      assert_includes response.body, @target.public_id

      export_log = AuditLog.find_by!(action: "system.audit.exported")
      assert_equal request.request_id, export_log.request_id
      assert_equal 1, export_log.metadata.fetch("exported_count")
      assert_equal "req-audit-123", export_log.metadata.dig("filters", "request_id")
    end
  end
end
