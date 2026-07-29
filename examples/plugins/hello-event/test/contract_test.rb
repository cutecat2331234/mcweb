# frozen_string_literal: true

require "test_helper"
require "mcweb/plugins/devtools"

class HelloEventReferencePluginContractTest < ActiveSupport::TestCase
  PLUGIN_ROOT = Pathname(__dir__).join("..").expand_path

  setup { Mcweb::Plugins.reset! }
  teardown { Mcweb::Plugins.reset! }

  test "declares settings translations event and admin page contributions" do
    report = Mcweb::Plugins::Devtools::Validator.new(path: PLUGIN_ROOT).call

    assert_predicate report, :ok?, report.errors.inspect
    manifest = Mcweb::Plugins::Manifest.load_file(PLUGIN_ROOT.join("mcweb_plugin.yml"))
    contributions = Mcweb::Plugins::ContributionDocumentLoader.load(manifest)
    assert_equal %w[event navigation page translation translation], contributions.map(&:type).sort
    assert_equal [ "enabled" ], Mcweb::Plugins::SettingSchemaLoader.load(manifest).properties.keys
  end

  test "handles a topic event and emits an immutable plugin event" do
    emitted = []
    subscriber = Mcweb::Events.subscribe("examples.hello_event.topic_seen") do |payload|
      emitted << payload
    end
    Mcweb::Plugins.reload!(root: PLUGIN_ROOT)

    Mcweb::Events.publish("forum.topic.created", topic_public_id: "topic-example")

    assert_equal "topic-example", emitted.sole.fetch("topic_public_id")
    assert emitted.sole.fetch("source_event_id").present?
  ensure
    Mcweb::Events.unsubscribe(subscriber) if subscriber
  end
end
