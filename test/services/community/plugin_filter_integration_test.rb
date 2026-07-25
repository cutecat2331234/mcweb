# frozen_string_literal: true

require "test_helper"
require "mcweb/plugins/registry"

class Community::PluginFilterIntegrationTest < ActiveSupport::TestCase
  class NullEventBus
    def subscribe(*) = Object.new
    def unsubscribe(*) = true
  end

  setup do
    @registry = Mcweb::Plugins::Registry.new(
      event_bus: NullEventBus.new,
      logger: Logger.new(IO::NULL)
    )
    @user = create_user(forum_trust_level_override: 1)
    suffix = SecureRandom.hex(5)
    category = Community::Category.create!(
      name: "Plugin filter #{suffix}",
      slug: "plugin-filter-#{suffix}"
    )
    @section = Community::Section.create!(
      category:,
      name: "Plugin filter",
      slug: "plugin-filter-section-#{suffix}",
      position: 0
    )
  end

  teardown do
    @registry.reset!
  end

  test "topic creation applies the stable plugin attribute filter before validation and persistence" do
    register do |plugin|
      plugin.filter("forum.topic.create.attributes") do |value, context|
        assert_equal @user.id, context.dig("user", "id")
        assert_equal @section.id, context.dig("section", "id")
        value.merge(
          "title" => "[Plugin] #{value.fetch('title')}",
          "body" => "#{value.fetch('body')}\n\nExtended by plugin"
        )
      end
    end
    @registry.boot!

    result = with_plugin_registry do
      Community::CreateTopic.call(
        user: @user,
        section: @section,
        title: "Release notes",
        body: "Original body"
      )
    end

    assert_predicate result, :success?
    assert_equal "[Plugin] Release notes", result.value.title
    assert_equal "Original body\n\nExtended by plugin", result.value.posts.first.body
  end

  test "reply creation applies plugin output while preserving core permission and state checks" do
    topic, = create_visible_forum_notification_resource(
      user: @user,
      title: "Plugin replies"
    )
    register do |plugin|
      plugin.filter("forum.post.create.attributes") do |value, context|
        assert_equal topic.id, context.dig("topic", "id")
        value.merge("body" => "#{value.fetch('body')} [filtered]")
      end
    end
    @registry.boot!

    result = with_plugin_registry do
      Community::CreatePost.call(
        user: @user,
        topic:,
        body: "Reply",
        skip_interval_check: true
      )
    end

    assert_predicate result, :success?
    assert_equal "Reply [filtered]", result.value.body

    topic.update!(locked: true)
    denied = with_plugin_registry do
      Community::CreatePost.call(
        user: @user,
        topic:,
        body: "Still denied",
        skip_interval_check: true
      )
    end
    assert_predicate denied, :failure?
    assert_equal "This topic is locked.", denied.error
  end

  test "topic and post edits apply filters before the normal core edit pipeline" do
    topic, opening_post = create_visible_forum_notification_resource(
      user: @user,
      title: "Original title"
    )
    register do |plugin|
      plugin.filter("forum.topic.edit.attributes") do |value|
        value.merge(
          "title" => "Filtered title",
          "title_provided" => true
        )
      end
      plugin.filter("forum.post.edit.attributes") do |value|
        value.merge(
          "body" => "#{value.fetch('body')} [filtered]",
          "reason" => "Plugin policy"
        )
      end
    end
    @registry.boot!

    topic_result = with_plugin_registry do
      Community::EditTopic.call(
        user: @user,
        topic:,
        title: "Requested title"
      )
    end
    post_result = with_plugin_registry do
      Community::EditPost.call(
        user: @user,
        post: opening_post,
        body: "Updated body",
        reason: "User reason"
      )
    end

    assert_predicate topic_result, :success?
    assert_equal "Filtered title", topic.reload.title
    assert_predicate post_result, :success?
    assert_equal "Updated body [filtered]", opening_post.reload.body
    assert_equal "Plugin policy", opening_post.edits.order(:id).last.reason
  end

  private

  def register(&block)
    @registry.register(
      id: "acme/forum-filter",
      name: "Forum filter",
      version: "1.0.0",
      api_version: "1",
      requires: {},
      capabilities: [ "forum.extend" ],
      &block
    )
  end

  def with_plugin_registry(&block)
    original = Mcweb::Plugins.method(:apply_filter)
    registry = @registry
    Mcweb::Plugins.singleton_class.define_method(:apply_filter) do |name, value, context: {}|
      registry.apply_filter(name, value, context:)
    end
    block.call
  ensure
    Mcweb::Plugins.singleton_class.define_method(:apply_filter, original) if original
  end
end
