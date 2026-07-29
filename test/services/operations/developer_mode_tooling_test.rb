# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "json"
require "tmpdir"

module Operations
  class DeveloperModeToolingTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      AuditDeveloperModeConfiguration.reset_process_cache!
    end

    test "configuration changes are persisted once with redacted summaries" do
      disabled = developer_settings(enabled: false)
      enabled = developer_settings(
        enabled: true,
        auto_login_user: "secret-owner@example.test"
      )

      assert_difference(
        -> { AuditLog.by_action("system.developer_mode_configuration_changed").count },
        1
      ) do
        AuditDeveloperModeConfiguration.call(settings: disabled)
      end
      assert_no_difference(
        -> { AuditLog.by_action("system.developer_mode_configuration_changed").count }
      ) do
        AuditDeveloperModeConfiguration.call(settings: disabled)
      end
      assert_difference(
        -> { AuditLog.by_action("system.developer_mode_configuration_changed").count },
        1
      ) do
        AuditDeveloperModeConfiguration.call(settings: enabled)
      end

      state = DeveloperModeRuntimeState.find(1)
      assert_predicate state, :enabled?
      assert_equal true,
        state.configuration_summary.fetch("auto_login_configured")
      refute_includes state.configuration_summary.to_json,
        "secret-owner@example.test"
    end

    test "scenario seeding is idempotent and personas are developer only" do
      first = with_settings(developer_settings(enabled: true)) do
        DeveloperScenarioSeeder.call(scenario: "all")
      end
      second = with_settings(developer_settings(enabled: true)) do
        DeveloperScenarioSeeder.call(scenario: "all")
      end

      assert_predicate first, :success?
      assert_predicate second, :success?
      assert_equal User::DEVELOPER_MODE_PERSONAS.sort,
        User.where.not(developer_mode_persona: nil)
          .pluck(:developer_mode_persona)
          .sort
      assert_equal 1,
        Community::Category.where(slug: "developer-mode").count
      assert_equal 1,
        Community::Section.where(slug: "playground").count
      assert_equal 1,
        Commerce::Product.where(
          slug: "developer-mode-test-product"
        ).count

      persona = User.find_by!(developer_mode_persona: "member")
      with_settings(developer_settings(enabled: true)) do
        assert_predicate persona, :session_eligible?
      end
      with_settings(developer_settings(enabled: false)) do
        assert_not persona.session_eligible?
        session_result = Identity::SessionManager.call(user: persona)
        assert_predicate session_result, :failure?
        assert_equal "session_ineligible", session_result.code
      end
    end

    test "capture browser paginates redacted metadata and clears only files" do
      Dir.mktmpdir("mcweb-developer-captures") do |directory|
        root = Pathname(directory)
        capture_directory =
          root.join("tmp/developer-mode/webhooks")
        FileUtils.mkdir_p(capture_directory)
        capture_path = capture_directory.join("capture.jsonl")
        secret = "secret-#{SecureRandom.hex(8)}"
        entries = 3.times.map do |index|
          {
            id: SecureRandom.uuid,
            captured_at: (Time.utc(2026, 7, 29, 10, index)).iso8601,
            method: "POST",
            url: "https://example.test/#{secret}",
            payload: { secret: secret }
          }
        end
        capture_path.write(
          entries.map { |entry| JSON.generate(entry) }.join("\n") + "\n"
        )

        store = DeveloperCaptureStore.new(root: root)
        first_page = store.page(
          kind: "webhooks",
          page: 1,
          per_page: 2
        )
        serialized = JSON.generate(first_page)

        assert_equal 2, first_page.fetch(:entries).length
        assert_equal true, first_page.fetch(:hasNextPage)
        refute_includes serialized, secret
        refute_includes serialized, "payload"
        refute_includes serialized, "url"

        result = store.clear!(kind: "webhooks")
        assert_equal 1, result.fetch(:deletedFiles)
        assert_not capture_path.exist?
        assert capture_directory.directory?
      end
    end

    test "attachment scenarios preserve structural guards and audit changes" do
      user = create_user
      upload = Community::Upload.create!(
        user: user,
        public_id: Community::Upload.generate_public_id,
        kind: "post_attachment",
        status: "stored",
        byte_size: 32,
        expires_at: 1.day.from_now
      )

      with_settings(developer_settings(enabled: true)) do
        %w[clean infected quarantined timeout].each do |scenario|
          result = DeveloperUploadScenario.call(
            upload: upload,
            scenario: scenario,
            actor: user
          )
          assert_predicate result, :success?, scenario
        end
      end

      assert_equal "error", upload.reload.scan_status
      assert_equal "developer_fixture_timeout", upload.scan_result_code
      assert_nil upload.quarantined_at
      assert upload.next_scan_at.future?
      assert_equal 4,
        AuditLog.by_action(
          "developer_mode.attachment_scenario_applied"
        ).count

      with_settings(developer_settings(enabled: false)) do
        result = DeveloperUploadScenario.call(
          upload: upload,
          scenario: "clean",
          actor: user
        )
        assert_predicate result, :failure?
        assert_equal "developer_mode_not_enabled", result.code
      end
    end

    test "manual task runner enqueues only its allowlist and records an audit" do
      actor = create_user

      with_settings(developer_settings(enabled: true)) do
        assert_enqueued_with(job: Maintenance::CleanupExpiredSessionsJob) do
          result = DeveloperTaskRunner.call(
            task: "cleanup_sessions",
            actor: actor
          )
          assert_predicate result, :success?
        end

        result = DeveloperTaskRunner.call(
          task: "Kernel.system",
          actor: actor
        )
        assert_predicate result, :failure?
        assert_equal "developer_task_invalid", result.code
      end

      assert_equal 1,
        AuditLog.by_action("developer_mode.task_triggered").count
    end

    private

    def developer_settings(enabled:, auto_login_user: nil)
      Mcweb::DeveloperMode.parse(
        config: {
          developer_mode: {
            enabled: enabled,
            auto_login_user: auto_login_user
          }
        },
        environment: {}
      )
    end

    def with_settings(settings)
      previous =
        Mcweb::DeveloperMode.instance_variable_get(:@settings)
      Mcweb::DeveloperMode.instance_variable_set(:@settings, settings)
      yield
    ensure
      Mcweb::DeveloperMode.instance_variable_set(:@settings, previous)
    end
  end
end
