# frozen_string_literal: true

require "test_helper"

class Mcweb::EventsTest < ActiveSupport::TestCase
  test "subscribers receive the published payload" do
    received = []
    sub = Mcweb::Events.subscribe("test.event.alpha") { |payload| received << payload }

    Mcweb::Events.publish("test.event.alpha", foo: "bar", n: 1)

    assert_equal 1, received.size
    assert_equal "bar", received.first[:foo]
    assert_equal 1, received.first[:n]
  ensure
    Mcweb::Events.unsubscribe(sub)
  end

  test "a raising listener is isolated and does not break publish or other listeners" do
    other_ran = false
    bad = Mcweb::Events.subscribe("test.event.beta") { raise "boom" }
    good = Mcweb::Events.subscribe("test.event.beta") { other_ran = true }

    assert_nothing_raised do
      assert_equal true, Mcweb::Events.publish("test.event.beta", x: 1)
    end
    assert other_ran, "second listener must still run after the first one raised"
  ensure
    Mcweb::Events.unsubscribe(bad)
    Mcweb::Events.unsubscribe(good)
  end

  test "full_name namespaces events and is idempotent" do
    assert_equal "forum.post.created.mcweb", Mcweb::Events.full_name("forum.post.created")
    assert_equal "forum.post.created.mcweb", Mcweb::Events.full_name("forum.post.created.mcweb")
  end

  test "subscribe requires a block" do
    assert_raises(ArgumentError) { Mcweb::Events.subscribe("test.event.gamma") }
  end

  test "deferred domain and raw notifications flush on success and discard on error" do
    domain_events = []
    raw_events = []
    domain = Mcweb::Events.subscribe("test.event.deferred") do |payload|
      domain_events << payload.fetch(:value)
    end
    raw = ActiveSupport::Notifications.subscribe("test.raw.deferred") do |notification|
      raw_events << notification.payload.fetch(:value)
    end

    assert_raises(RuntimeError) do
      Mcweb::Events.defer_until_success do
        Mcweb::Events.publish("test.event.deferred", value: "discarded")
        Mcweb::Events.publish_notification("test.raw.deferred", value: "discarded")
        raise "rollback"
      end
    end
    assert_empty domain_events
    assert_empty raw_events

    Mcweb::Events.defer_until_success do
      Mcweb::Events.publish("test.event.deferred", value: "committed")
      Mcweb::Events.publish_notification("test.raw.deferred", value: "committed")
    end
    assert_equal [ "committed" ], domain_events
    assert_equal [ "committed" ], raw_events
  ensure
    Mcweb::Events.unsubscribe(domain) if domain
    ActiveSupport::Notifications.unsubscribe(raw) if raw
  end

  test "catalog lists documented core events" do
    assert_includes Mcweb::Events::CATALOG, "forum.post.created"
    assert_includes Mcweb::Events::CATALOG, "forum.reaction.added"
    assert_includes Mcweb::Events::CATALOG, "identity.user.registered"
    assert_includes Mcweb::Events::CATALOG, "plugin.settings.changed"
  end
end

class Mcweb::EventsWiringTest < ActiveSupport::TestCase
  setup do
    category = Community::Category.find_or_create_by!(slug: "evt-cat") { |c| c.name = "Evt" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "evt-sec") do |s|
      s.name = "Evt Section"
      s.position = 0
    end
    @author = create_user(username: "evtauthor")
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @author,
      title: "Event topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @author,
      replies_count: 0
    )
    @post = Community::Post.create!(topic: @topic, user: @author, floor_number: 1, body: "OP body", status: "published")
  end

  test "DispatchForumEventWebhook emits the internal bus event even without a webhook url" do
    SiteSetting.set("forum.event_webhook_url", "")
    events = []
    sub = Mcweb::Events.subscribe("forum.post.created") { |payload| events << payload }

    result = Community::DispatchForumEventWebhook.call(event_type: "post.created", topic: @topic, post: @post)

    assert result.success?
    assert_equal 1, events.size
    assert_equal @topic.id, events.first[:topic].id
    assert_equal @post.id, events.first[:post].id
  ensure
    Mcweb::Events.unsubscribe(sub)
  end

  test "ToggleReaction publishes forum.reaction.added" do
    reactor = create_user(username: "evtreactor")
    events = []
    sub = Mcweb::Events.subscribe("forum.reaction.added") { |payload| events << payload }

    result = Community::ToggleReaction.call(user: reactor, post: @post, emoji: "👍")

    assert result.success?
    assert_equal 1, events.size
    assert_equal @post.id, events.first[:post].id
    assert_equal reactor.id, events.first[:user].id
  ensure
    Mcweb::Events.unsubscribe(sub)
  end

  test "RegisterUser publishes identity.user.registered" do
    events = []
    sub = Mcweb::Events.subscribe("identity.user.registered") { |payload| events << payload }

    result = Identity::RegisterUser.call(
      email: "evt-#{SecureRandom.hex(4)}@example.com",
      username: "evtreg#{SecureRandom.hex(3)}",
      password: "password123",
      ip_address: "127.0.0.1"
    )

    assert result.success?
    assert_equal 1, events.size
    assert_equal result.value[:user].id, events.first[:user].id
  ensure
    Mcweb::Events.unsubscribe(sub)
  end
end
