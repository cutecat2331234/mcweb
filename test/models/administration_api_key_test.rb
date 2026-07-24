# frozen_string_literal: true

require "test_helper"

class AdministrationApiKeyTest < ActiveSupport::TestCase
  test "generate requires at least one valid scope" do
    assert_raises(ArgumentError) do
      Administration::ApiKey.generate!(name: "empty", scopes: [])
    end
    assert_raises(ArgumentError) do
      Administration::ApiKey.generate!(name: "unknown", scopes: %w[admin])
    end
  end

  test "authenticate rejects a key bound to a banned or deleted user" do
    banned_user = create_user
    _banned_key, banned_token = Administration::ApiKey.generate!(
      name: "banned",
      scopes: %w[read],
      user: banned_user
    )
    banned_user.ban!(reason: "test")
    assert_nil Administration::ApiKey.authenticate(banned_token)

    deleted_user = create_user
    deleted_key, deleted_token = Administration::ApiKey.generate!(
      name: "deleted",
      scopes: %w[read],
      user: deleted_user
    )
    deleted_user.soft_delete!
    assert deleted_key.reload.revoked?
    assert_nil Administration::ApiKey.authenticate(deleted_token)
  end

  test "banning a user revokes their active api keys" do
    actor = create_user
    target = create_user
    key, = Administration::ApiKey.generate!(name: "active", scopes: %w[read], user: target)

    result = Administration::BanUser.call(user: target, actor: actor, reason: "test")

    assert result.success?
    assert key.reload.revoked?
  end
end
