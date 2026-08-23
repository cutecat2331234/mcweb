# frozen_string_literal: true

require "test_helper"
require "mcweb/plugins/registry"

class Mcweb::PluginApi::V1::HostTest < ActiveSupport::TestCase
  class FakeEventBus
    attr_reader :published

    def initialize
      @published = []
    end

    def publish(event, payload)
      @published << [ event, payload ]
      true
    end
  end

  setup do
    suffix = SecureRandom.hex(4)
    @category = Community::Category.create!(
      name: "Plugin API #{suffix}",
      slug: "plugin-api-#{suffix}"
    )
    @public_section = Community::Section.create!(
      category: @category,
      name: "Public",
      slug: "plugin-public-#{suffix}",
      position: 0
    )
    @restricted_section = Community::Section.create!(
      category: @category,
      name: "Restricted",
      slug: "plugin-restricted-#{suffix}",
      position: 1,
      permissions: { "view" => [ "forum.plugin_private.view" ] }
    )
    @author = create_user
    @member = create_user
    @allowed_member = create_user
    grant_permission(@allowed_member, "forum.plugin_private.view")
    @public_topic, @public_post = create_topic_with_post(
      section: @public_section,
      title: "Public plugin topic"
    )
    @restricted_topic, @restricted_post = create_topic_with_post(
      section: @restricted_section,
      title: "Restricted plugin topic"
    )
    @hidden_topic, @hidden_post = create_topic_with_post(
      section: @public_section,
      title: "Hidden plugin topic",
      status: "hidden"
    )
    @event_bus = FakeEventBus.new
    @api = Mcweb::PluginApi::V1::Host.new(
      manifest: manifest,
      event_bus: @event_bus
    )
  end

  test "forum scopes and finders never expose records outside canonical access policies" do
    sections = @api.forum.sections(user: @member)
    assert_predicate sections, :success?
    assert_includes sections.value.pluck("id"), @public_section.id
    assert_not_includes sections.value.pluck("id"), @restricted_section.id

    topics = @api.forum.topics(user: @member)
    assert_includes topics.value.pluck("id"), @public_topic.id
    assert_not_includes topics.value.pluck("id"), @restricted_topic.id
    assert_not_includes topics.value.pluck("id"), @hidden_topic.id

    assert_not_visible @api.forum.find_section(user: @member, id: @restricted_section.id)
    assert_not_visible @api.forum.find_topic(user: @member, public_id: @restricted_topic.public_id)
    assert_not_visible @api.forum.find_post(user: @member, id: @restricted_post.id)
    assert_not_visible @api.forum.posts(user: @member, topic_id: @restricted_topic.id)

    allowed_topic = @api.forum.find_topic(
      user: @allowed_member,
      public_id: @restricted_topic.public_id
    )
    assert_predicate allowed_topic, :success?
    assert_equal @restricted_topic.id, allowed_topic.value.fetch("id")

    public_post = @api.forum.find_post(user: nil, id: @public_post.id)
    assert_predicate public_post, :success?
    assert_equal @public_post.body, public_post.value.fetch("body")
    assert_predicate public_post, :frozen?
    assert_predicate public_post.value, :frozen?
    assert_raises(FrozenError) { public_post.value["body"] = "changed" }
    refute public_post.value.values.any? { |value| value.is_a?(ActiveRecord::Base) }
    refute_includes public_post.value.keys, "email"
  end

  test "forum writes delegate to core services and return immutable snapshots" do
    writer = create_user
    topic_result = @api.forum.create_topic(
      user: writer,
      section_slug: @public_section.slug,
      title: "Created through plugin API",
      body: "Opening post through the core service",
      ip_address: "127.0.0.1"
    )

    assert_predicate topic_result, :success?
    assert_equal "ok", topic_result.code
    assert_equal "forum.topic", topic_result.value.fetch("type")
    topic = Community::Topic.find(topic_result.value.fetch("id"))
    assert Community::Subscription.exists?(user: writer, subscribable: topic)
    assert_predicate topic_result.to_h, :frozen?

    travel 11.seconds do
      post_result = @api.forum.create_post(
        user: writer,
        topic_public_id: topic.public_id,
        body: "Reply through the existing CreatePost service",
        ip_address: "127.0.0.1"
      )

      assert_predicate post_result, :success?
      assert_equal "forum.post", post_result.value.fetch("type")
      assert_equal topic.id, post_result.value.fetch("topic_id")
    end

    failure = @api.forum.create_topic(
      user: @member,
      section_id: @restricted_section.id,
      title: "Must not exist",
      body: "Must not be written"
    )
    assert_not_visible failure

    service_failure = @api.forum.create_topic(
      user: create_user,
      section_id: @public_section.id,
      title: "",
      body: "Valid body"
    )
    assert_predicate service_failure, :failure?
    assert_equal "service_failure", service_failure.code
    assert_predicate service_failure.errors, :frozen?

    assert_raises(ArgumentError) do
      @api.forum.create_post(
        user: writer,
        topic_id: topic.id,
        body: "No bypass",
        skip_interval_check: true
      )
    end
  end

  test "events and site reads use the versioned result boundary" do
    catalog = @api.events.catalog
    assert_predicate catalog, :success?
    assert_includes catalog.value, "forum.post.created"

    published = @api.events.publish("acme.demo.completed", count: 2)
    assert_predicate published, :success?
    assert_equal [ [ "acme.demo.completed", { count: 2 } ] ], @event_bus.published

    invalid = @api.events.publish("invalid", {})
    assert_predicate invalid, :failure?
    assert_equal "invalid_argument", invalid.code

    key = "plugin.api.#{SecureRandom.hex(4)}"
    SiteSetting.set(key, "configured")
    setting = @api.site.setting(key, default: "fallback")
    assert_equal "configured", setting.value
    assert_predicate setting.value, :frozen?

    secret_key = "plugin.api.delivery_token"
    secret = "must-not-leave-host-#{SecureRandom.hex(8)}"
    SiteSetting.set(secret_key, secret)
    sensitive = @api.site.setting(secret_key)
    assert_predicate sensitive, :failure?
    assert_equal "setting_sensitive", sensitive.code
    refute_includes sensitive.to_h.to_json, secret

    features = @api.site.features
    assert_equal FeatureFlags.frontend_hash, features.value
    assert_equal FeatureFlags.enabled?(:forum), @api.site.feature("forum").value
    assert_equal "not_found", @api.site.feature("unknown").code
  end

  test "host identity and result values are versioned and immutable" do
    assert_equal "acme/host-api", @api.plugin_id
    assert_equal "1", @api.api_version
    assert @api.declares_capability?("forum.read")
    refute @api.declares_capability?("forum.moderate")
    assert_predicate @api, :frozen?
    assert_predicate @api.to_h, :frozen?

    invalid = @api.forum.find_topic(user: Object.new, id: @public_topic.id)
    assert_predicate invalid, :failure?
    assert_equal "1", invalid.schema_version
    assert_equal "invalid_user", invalid.code
    assert_predicate invalid.to_h, :frozen?
  end

  test "host facades convert infrastructure exceptions into immutable results" do
    exploding_feature = Object.new
    exploding_feature.define_singleton_method(:to_sym) do
      raise "feature backend unavailable"
    end
    site_result = @api.site.feature(exploding_feature)
    assert_predicate site_result, :failure?
    assert_equal "host_error", site_result.code
    assert_includes site_result.error, "RuntimeError: feature backend unavailable"
    assert_predicate site_result, :frozen?

    exploding_user = @member.dup
    exploding_user.define_singleton_method(:persisted?) do
      raise "forum backend unavailable"
    end
    forum_result = @api.forum.sections(user: exploding_user)
    assert_predicate forum_result, :failure?
    assert_equal "host_error", forum_result.code
    assert_includes forum_result.error, "RuntimeError: forum backend unavailable"

    failing_event_bus = Object.new
    failing_event_bus.define_singleton_method(:publish) do |*|
      raise "event backend unavailable"
    end
    events = Mcweb::PluginApi::V1::Events.new(event_bus: failing_event_bus)
    event_result = events.publish("acme.demo.failure", value: 1)
    assert_predicate event_result, :failure?
    assert_equal "event_publish_failed", event_result.code
    assert_includes event_result.error, "RuntimeError: event backend unavailable"
    assert_predicate event_result.to_h, :frozen?
  end

  test "normalization bounds deeply nested values without losing immutability" do
    nested = "leaf"
    (Mcweb::PluginApi::V1::Normalizer::MAX_DEPTH + 10).times do
      nested = [ nested ]
    end

    result = Mcweb::PluginApi::V1::Result.success(nested)
    cursor = result.value
    cursor = cursor.first while cursor.is_a?(Array)

    assert_equal({ "type" => "maximum_depth" }, cursor)
    assert_predicate cursor, :frozen?
    assert_predicate result.value, :frozen?
  end

  test "event names are length bounded at registration and publication" do
    long_event = "acme.#{'x' * 200}"
    result = @api.events.publish(long_event, {})

    assert_predicate result, :failure?
    assert_equal "invalid_argument", result.code

    registry = Mcweb::Plugins::Registry.new(
      event_bus: FakeEventBus.new,
      logger: Logger.new(IO::NULL)
    )
    assert_raises(ArgumentError) do
      registry.register(manifest) do |plugin|
        plugin.on(long_event) { nil }
      end
    end
  ensure
    registry&.reset!
  end

  private

  def manifest
    Mcweb::Plugins::Manifest.from_hash({
      id: "acme/host-api",
      name: "Host API",
      version: "1.0.0",
      api_version: "1",
      capabilities: %w[
        forum.events.publish
        forum.events.read
        forum.read
        forum.write
        site.features.read
        site.settings.read
      ]
    })
  end

  def create_topic_with_post(section:, title:, status: "published")
    topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section:,
      user: @author,
      title:,
      status:,
      last_posted_at: Time.current,
      last_post_user: @author,
      replies_count: 0
    )
    post = Community::Post.create!(
      topic:,
      user: @author,
      floor_number: 1,
      body: "#{title} body",
      status: "published"
    )
    [ topic, post ]
  end

  def assert_not_visible(result)
    assert_predicate result, :failure?
    assert_equal "not_found", result.code
    assert_match(/not found or not visible/, result.error)
  end
end
