# frozen_string_literal: true

require "test_helper"

module Community
  class DeveloperModeAttachmentGuardsTest < ActiveSupport::TestCase
    setup do
      @user = create_user
    end

    test "unrestricted mode assumes attachments are clean without invoking ClamAV" do
      scanner_called = false
      runner = lambda do |_argv, timeout_seconds:|
        scanner_called = true
        assert_equal 60, timeout_seconds
        Community::AttachmentMalwareScanner::ClamavCommandAdapter::RunResult.new(
          exit_status: 0,
          stdout: "OK",
          stderr: "",
          timed_out: false
        )
      end
      adapter = Community::AttachmentMalwareScanner::ClamavCommandAdapter.new(
        executable: "clamscan",
        runner: runner
      )
      blob = Object.new
      blob.define_singleton_method(:open) do |&block|
        block.call(Struct.new(:path).new("C:/tmp/developer-mode-upload"))
      end

      result = with_developer_mode(enabled: true) do
        Community::AttachmentMalwareScanner.call(blob: blob, adapter: adapter)
      end

      assert_not scanner_called
      assert_predicate result, :clean?
      assert_equal :clean, result.status
      assert_equal "developer_mode", result.scanner
      assert_equal "dev_bypassed", result.code
      assert_nil result.error_message
    end

    test "disabled mode preserves configured scanner behavior" do
      scanner_called = false
      adapter = Object.new
      adapter.define_singleton_method(:scan) do |blob:|
        scanner_called = true
        raise "missing blob" unless blob

        Community::AttachmentMalwareScanner::Result.new(
          status: :infected,
          scanner: "test_scanner",
          code: "malware_detected",
          error_message: nil
        )
      end

      result = with_developer_mode(enabled: false) do
        Community::AttachmentMalwareScanner.call(blob: Object.new, adapter: adapter)
      end

      assert scanner_called
      assert_predicate result, :infected?
      assert_equal "test_scanner", result.scanner
      assert_equal "malware_detected", result.code
    end

    test "unrestricted mode bypasses quota limits but keeps upload reservations" do
      SiteSetting.set("forum.upload_quota.account.count", "1")

      first, second = with_developer_mode(enabled: true) do
        [
          Community::UploadQuota.call(
            user: @user,
            kind: :inline_image,
            byte_size: 1
          ),
          Community::UploadQuota.call(
            user: @user,
            kind: :post_attachment,
            byte_size: 1
          )
        ]
      end

      assert_predicate first, :success?
      assert_predicate second, :success?
      assert_equal 2, Community::Upload.where(user: @user).count
      assert_equal %w[reserved reserved],
        Community::Upload.where(user: @user).order(:id).pluck(:status)
      assert first.value.public_id.present?
      assert second.value.public_id.present?
      assert_equal 1, first.value.byte_size
      assert_equal 1, second.value.byte_size
    end

    test "disabled mode still rejects uploads that exceed quota" do
      SiteSetting.set("forum.upload_quota.account.count", "1")

      first, second = with_developer_mode(enabled: false) do
        [
          Community::UploadQuota.call(
            user: @user,
            kind: :inline_image,
            byte_size: 1
          ),
          Community::UploadQuota.call(
            user: @user,
            kind: :post_attachment,
            byte_size: 1
          )
        ]
      end

      assert_predicate first, :success?
      assert_predicate second, :failure?
      assert_equal "upload_quota_exceeded", second.code
      assert_equal "account", second.value.fetch(:scope)
      assert_equal "count", second.value.fetch(:metric)
      assert_equal 1, Community::Upload.where(user: @user).count
    end

    private

    def with_developer_mode(enabled:, &block)
      settings = Mcweb::DeveloperMode.parse(
        config: {
          developer_mode: {
            enabled: enabled,
            preset: "unrestricted"
          }
        },
        environment: {}
      )

      previous_settings = Mcweb::DeveloperMode.instance_variable_get(:@settings)
      Mcweb::DeveloperMode.instance_variable_set(:@settings, settings)
      block.call
    ensure
      Mcweb::DeveloperMode.instance_variable_set(:@settings, previous_settings)
    end
  end
end
