# frozen_string_literal: true

require "test_helper"

module Community
  class UserProfileActivitySerializerTest < ActiveSupport::TestCase
    setup do
      @user = create_user
      @user.update!(last_seen_at: 1.minute.ago)
      account = Community::PointAccount.create!(user: @user, currency: "points", balance: 42)
      Community::PointTransaction.create!(
        account: account,
        user: @user,
        currency: "points",
        reason: "serializer_test",
        amount: 42,
        balance_after: 42
      )
      Community::CheckIn.create!(
        user: @user,
        checked_on: Date.current,
        streak: 2,
        points_awarded: 1
      )
      Commerce::Order.create!(
        user: @user,
        status: "paid",
        subtotal_cents: 100,
        discount_cents: 0,
        total_cents: 100,
        currency: "CNY"
      )
      Commerce::Order.create!(
        user: @user,
        status: "cancelled",
        subtotal_cents: 100,
        discount_cents: 0,
        total_cents: 100,
        currency: "CNY"
      )
    end

    test "hidden surfaces return no activity keys and do not query game presence" do
      serializer = UserProfileActivitySerializer.new(user: @user, viewer: nil)

      Minecraft::IngameStatusForUser.stub(:call, ->(user:) { flunk("queried hidden game presence for #{user.id}") }) do
        assert_equal({}, serializer.card)
      end
      assert_equal({}, serializer.profile)
      assert_equal({}, serializer.member(purchases_count: 1))
      assert_equal({}, serializer.minecraft(identity: Struct.new(:last_seen_ingame_at).new(Time.current)))
    end

    test "public opt in exposes only the bounded activity summary" do
      @user.update!(forum_profile_activity_public: true)
      serializer = UserProfileActivitySerializer.new(user: @user, viewer: nil)
      ingame = ServiceResult.success(ingame_online: true, ingame_server: "Private Lobby")

      card = Minecraft::IngameStatusForUser.stub(:call, ingame) { serializer.card }
      assert_equal %i[ingame_online ingame_server last_seen_at online], card.keys.sort
      assert_equal true, card.fetch(:ingame_online)
      assert_equal "Private Lobby", card.fetch(:ingame_server)

      profile = serializer.profile
      assert_equal %i[
        check_in_streak check_in_total forum_points last_seen_at online orders_count
      ].sort, profile.keys.sort
      assert_equal 42, profile.fetch(:forum_points)
      assert_equal 2, profile.fetch(:check_in_streak)
      assert_equal 1, profile.fetch(:check_in_total)
      assert_equal 1, profile.fetch(:orders_count)
      refute profile.key?(:recent_point_transactions)

      assert_equal %i[last_seen_at online purchases_count].sort,
                   serializer.member(purchases_count: 1).keys.sort
      identity = Struct.new(:last_seen_ingame_at).new(2.minutes.ago)
      assert_equal [ :last_seen_ingame_at ], serializer.minecraft(identity: identity).keys
    end

    test "the owner and explicitly authorized viewers retain private transaction history" do
      owner_profile = UserProfileActivitySerializer.new(user: @user, viewer: @user).profile
      assert_equal 1, owner_profile.fetch(:recent_point_transactions).size

      viewer = create_user
      grant_permission(viewer, UserProfileVisibility::PRIVATE_ACTIVITY_PERMISSION)
      authorized_profile = UserProfileActivitySerializer.new(user: @user, viewer: viewer).profile

      transaction = authorized_profile.fetch(:recent_point_transactions).first
      assert_equal 42, transaction.fetch(:amount)
      assert_equal 42, transaction.fetch(:balance_after)
    end
  end
end
