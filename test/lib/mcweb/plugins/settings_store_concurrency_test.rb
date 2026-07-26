# frozen_string_literal: true

require "test_helper"
require "mcweb/plugins/settings_store"

class Mcweb::Plugins::SettingsStoreConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @plugin_id = "acme/concurrent"
    @schema = Mcweb::Plugins::SettingSchema.new(
      plugin_id: @plugin_id,
      document: schema_document
    )
  end

  teardown do
    version_ids = PluginSettingVersion.where(plugin_id: @plugin_id).pluck(:id)
    AuditLog.where(
      resource_type: "PluginSettingVersion",
      resource_id: version_ids
    ).delete_all
    PluginSettingVersion.where(id: version_ids).delete_all
  end

  test "plugin-wide advisory locking allows only one stale concurrent revision" do
    ready = Queue.new
    gate = Queue.new
    outcomes = Queue.new
    events = Queue.new
    subscriber = Mcweb::Events.subscribe("plugin.settings.changed") do |payload|
      events << payload
    end

    threads = 2.times.map do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          store = Mcweb::Plugins::SettingsStore.new(
            plugin_id: @plugin_id,
            schema: @schema
          )
          ready << true
          gate.pop
          begin
            outcomes << store.update(
              values: { "endpoint" => "https://worker-#{index}.example.test" },
              expected_revision: 0
            )
          rescue Mcweb::Plugins::SettingValidationError => e
            outcomes << e
          end
        end
      end
    end

    2.times { ready.pop }
    2.times { gate << true }
    threads.each(&:join)
    results = 2.times.map { outcomes.pop }

    assert_equal 1, results.count { |result| result.is_a?(Mcweb::Plugins::SettingsStore::Snapshot) }
    assert_equal 1, results.count {
      |result| result.is_a?(Mcweb::Plugins::SettingValidationError) &&
        result.code == "revision_conflict"
    }
    assert_equal 1, PluginSettingVersion.where(plugin_id: @plugin_id).count
    assert_equal(
      1,
      AuditLog.where(action: "plugin.settings.update", resource_id: version_ids).count
    )
    event = events.pop(true)
    assert_equal @plugin_id, event.fetch(:plugin_id)
    assert_equal [ "endpoint" ], event.fetch(:changed_keys)
    refute_includes event.to_json, "worker-"
    assert_predicate events, :empty?
  ensure
    Mcweb::Events.unsubscribe(subscriber) if subscriber
  end

  private

  def version_ids
    PluginSettingVersion.where(plugin_id: @plugin_id).pluck(:id)
  end

  def schema_document
    {
      "schema_version" => "1",
      "groups" => {
        "general" => {
          "title_phrase" => "acme.concurrent.settings.general.title",
          "position" => 10
        }
      },
      "schema" => {
        "$schema" => Mcweb::Plugins::SettingSchema::DRAFT_URI,
        "type" => "object",
        "additionalProperties" => false,
        "required" => [ "endpoint" ],
        "properties" => {
          "endpoint" => {
            "type" => "string",
            "format" => "url",
            "x-mcweb-title-phrase" => "acme.concurrent.settings.endpoint.title",
            "x-mcweb-group" => "general",
            "x-mcweb-input" => "url"
          }
        }
      },
      "migrations" => []
    }
  end
end
