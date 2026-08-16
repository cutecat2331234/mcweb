# frozen_string_literal: true

require "test_helper"

module Minecraft
  class IdentityUnlinkRestrictionsTest < ActiveSupport::TestCase
    setup do
      @user = create_user
      @link = create_bound_account(user: @user)
      @registry = IdentityUnlinkRestrictions.new(logger: Logger.new(IO::NULL))
    end

    test "registered checkers allow with nil and deny with a stable downstream code" do
      seen = nil
      @registry.register(key: "example.audit") do |user:, identity_link:|
        seen = [ user, identity_link ]
        nil
      end
      @registry.register(key: "example.active_workflow") do |user:, identity_link:|
        :example_identity_unlink_active_workflow if user == @user && identity_link == @link
      end

      result = @registry.check(user: @user, identity_link: @link)

      assert_equal [ @user, @link ], seen
      assert_predicate result, :failure?
      assert_equal "example_identity_unlink_active_workflow", result.code
      assert_equal [ "example.audit", "example.active_workflow" ], @registry.registered_keys
    end

    test "service results are supported and checker failures fail closed" do
      denial = ServiceResult.failure(error: :example_denied, code: :example_denied)
      @registry.register(key: "example.service_result", callable: ->(**) { denial })
      assert_same denial, @registry.check(user: @user, identity_link: @link)

      failed_registry = IdentityUnlinkRestrictions.new(logger: Logger.new(IO::NULL))
      failed_registry.register(key: "example.failure") { raise "downstream unavailable" }
      failed = failed_registry.check(user: @user, identity_link: @link)
      assert_predicate failed, :failure?
      assert_equal "minecraft_identity_unlink_restriction_unavailable", failed.code

      malformed_registry = IdentityUnlinkRestrictions.new(logger: Logger.new(IO::NULL))
      malformed_registry.register(key: "example.malformed") { true }
      malformed = malformed_registry.check(user: @user, identity_link: @link)
      assert_predicate malformed, :failure?
      assert_equal "minecraft_identity_unlink_restriction_unavailable", malformed.code

      uncoded_registry = IdentityUnlinkRestrictions.new(logger: Logger.new(IO::NULL))
      uncoded_registry.register(key: "example.uncoded") do
        ServiceResult.failure(error: "unstructured downstream failure")
      end
      uncoded = uncoded_registry.check(user: @user, identity_link: @link)
      assert_predicate uncoded, :failure?
      assert_equal "minecraft_identity_unlink_restriction_unavailable", uncoded.code
    end

    test "registration names duplicates and total cardinality are bounded" do
      registry = IdentityUnlinkRestrictions.new(max_registrations: 1, logger: Logger.new(IO::NULL))

      assert_raises(ArgumentError) { registry.register(key: "Bad key") { nil } }
      registry.register(key: "example.first") { nil }
      assert_raises(ArgumentError) { registry.register(key: "example.first") { nil } }
      assert_raises(ArgumentError) { registry.register(key: "example.second") { nil } }
      assert_raises(ArgumentError) do
        IdentityUnlinkRestrictions.new(
          max_registrations: IdentityUnlinkRestrictions::MAX_REGISTRATIONS + 1
        )
      end
    end

    private

    def create_bound_account(user:)
      profile = Minecraft::PlayerProfile.create!
      Minecraft::PlayerIdentity.create!(
        player_profile: profile,
        platform: "java",
        external_uuid: SecureRandom.uuid,
        username: "Guarded",
        identity_type: "java",
        valid_from: Time.current
      )
      Minecraft::IdentityLink.create!(user: user, player_profile: profile, linked_at: Time.current)
    end
  end
end
