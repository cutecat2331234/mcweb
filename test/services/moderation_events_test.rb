# frozen_string_literal: true

require "test_helper"

class ModerationEventsTest < ActiveSupport::TestCase
  test "BanUser publishes identity.user.banned" do
    actor = create_user(username: "modactor1")
    target = create_user(username: "modtarget1")
    events = []
    sub = Mcweb::Events.subscribe("identity.user.banned") { |p| events << p }

    result = Administration::BanUser.call(user: target, actor: actor, reason: "spam")

    assert result.success?
    assert_equal 1, events.size
    assert_equal target.id, events.first[:user].id
    assert_equal actor.id, events.first[:actor].id
  ensure
    Mcweb::Events.unsubscribe(sub)
  end

  test "CreateUserWarning publishes forum.warning.issued" do
    actor = create_user(username: "modactor2")
    grant_permission(actor, "forum.users.warn")
    target = create_user(username: "modtarget2")
    events = []
    sub = Mcweb::Events.subscribe("forum.warning.issued") { |p| events << p }

    result = Community::CreateUserWarning.call(actor: actor, user: target, reason: "Be nice", points: 2)

    assert result.success?
    assert_equal 1, events.size
    assert_equal target.id, events.first[:user].id
    assert_equal result.value.id, events.first[:warning].id
  ensure
    Mcweb::Events.unsubscribe(sub)
  end

  test "SerializeEventPayload serializes moderation events to identifiers only" do
    actor = create_user(username: "modactor3")
    grant_permission(actor, "forum.users.warn")
    target = create_user(username: "modtarget3")
    warning = Community::CreateUserWarning.call(actor: actor, user: target, reason: "x", points: 1).value

    payload = Administration::SerializeEventPayload.call(
      event: "forum.warning.issued", payload: { user: target, actor: actor, warning: warning }
    )
    assert_equal warning.id, payload["data"]["warning"]["id"]
    assert_equal target.public_id, payload["data"]["user"]["id"]
    refute_includes payload.to_json, target.username
    refute_match(/reason|username|type/i, payload.to_json)
  end

  test "new events are in the catalog" do
    assert_includes Mcweb::Events::CATALOG, "identity.user.banned"
    assert_includes Mcweb::Events::CATALOG, "forum.warning.issued"
  end
end
