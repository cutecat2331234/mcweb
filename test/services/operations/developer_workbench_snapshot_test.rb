# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "json"
require "tmpdir"

module Operations
  class DeveloperWorkbenchSnapshotTest < ActiveSupport::TestCase
    test "capture summaries expose only bounded whitelisted metadata" do
      Dir.mktmpdir("mcweb-workbench") do |directory|
        root = Pathname(directory)
        mail_directory = root.join("tmp/developer-mode/mails")
        webhook_directory = root.join("tmp/developer-mode/webhooks")
        push_directory = root.join("tmp/developer-mode/web-push")
        [ mail_directory, webhook_directory, push_directory ].each do |path|
          FileUtils.mkdir_p(path)
        end

        sensitive = "must-never-be-returned-#{SecureRandom.hex(10)}"
        mail_directory.join("message.eml").write(
          "To: #{sensitive}@example.test\n\n#{sensitive}"
        )

        webhook_id = SecureRandom.uuid
        webhook_directory.join("2026-07-26.jsonl").write(
          JSON.generate(
            id: webhook_id,
            captured_at: "2026-07-26T10:00:00Z",
            method: "POST",
            url: "https://#{sensitive}.example.test/hook?token=#{sensitive}",
            headers: { authorization: sensitive },
            payload: { secret: sensitive }
          ) + "\n"
        )

        push_id = SecureRandom.uuid
        push_directory.join("2026-07-26.jsonl").write(
          JSON.generate(
            id: push_id,
            captured_at: "2026-07-26T10:01:00Z",
            notification: {
              id: 99,
              type: "mention",
              user_id: sensitive
            },
            payload: { body: sensitive }
          ) + "\n"
        )

        snapshot = with_developer_mode(
          auto_login_user: sensitive
        ) do
          DeveloperWorkbenchSnapshot.call(root: root)
        end
        serialized = JSON.generate(snapshot)

        assert_equal true, snapshot.fetch(:autoLoginConfigured)
        assert_equal webhook_id.first(8),
          snapshot.dig(
            :captures,
            :webhooks,
            :latestEntries,
            0,
            :captureRef
          )
        assert_equal "POST",
          snapshot.dig(
            :captures,
            :webhooks,
            :latestEntries,
            0,
            :method
          )
        assert_equal "mention",
          snapshot.dig(
            :captures,
            :webPush,
            :latestEntries,
            0,
            :notificationType
          )
        assert_equal 1,
          snapshot.dig(:captures, :mail, :latestEntries).length

        refute_includes serialized, sensitive
        refute_includes serialized, root.to_s
        refute_includes serialized, "message.eml"
        refute_includes serialized, "payload"
        refute_includes serialized, webhook_id
        refute_includes serialized, push_id
      end
    end

    test "invalid capture fields are rejected or normalized" do
      Dir.mktmpdir("mcweb-workbench") do |directory|
        root = Pathname(directory)
        webhook_directory = root.join("tmp/developer-mode/webhooks")
        push_directory = root.join("tmp/developer-mode/web-push")
        FileUtils.mkdir_p(webhook_directory)
        FileUtils.mkdir_p(push_directory)

        webhook_directory.join("capture.jsonl").write(
          [
            "{not-json}",
            JSON.generate(
              id: SecureRandom.uuid,
              captured_at: "2026-07-26T10:00:00Z",
              method: "SECRET_METHOD"
            )
          ].join("\n") + "\n"
        )
        push_directory.join("capture.jsonl").write(
          JSON.generate(
            id: SecureRandom.uuid,
            captured_at: "2026-07-26T10:00:00Z",
            notification: {
              type: "private value with spaces"
            }
          ) + "\n"
        )

        snapshot = with_developer_mode do
          DeveloperWorkbenchSnapshot.call(root: root)
        end

        assert_equal "OTHER",
          snapshot.dig(
            :captures,
            :webhooks,
            :latestEntries,
            0,
            :method
          )
        assert_equal "other",
          snapshot.dig(
            :captures,
            :webPush,
            :latestEntries,
            0,
            :notificationType
          )
      end
    end

    private

    def with_developer_mode(auto_login_user: nil)
      settings = Mcweb::DeveloperMode.parse(
        config: {
          developer_mode: {
            enabled: true,
            auto_login_user: auto_login_user
          }
        },
        environment: {}
      )
      previous_settings =
        Mcweb::DeveloperMode.instance_variable_get(:@settings)
      Mcweb::DeveloperMode.instance_variable_set(:@settings, settings)
      yield
    ensure
      Mcweb::DeveloperMode.instance_variable_set(:@settings, previous_settings)
    end
  end
end
