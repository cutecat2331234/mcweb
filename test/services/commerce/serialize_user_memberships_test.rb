# frozen_string_literal: true

require "test_helper"

module Commerce
  class SerializeUserMembershipsTest < ActiveSupport::TestCase
    setup do
      @user = create_user
      @other_user = create_user
      @membership = create_membership(user: @user, name: "Member plan")
      @other_membership = create_membership(user: @other_user, name: "Other plan")
    end

    test "serializes memberships for only the requested user" do
      result = SerializeUserMemberships.for_user(@user)

      assert_equal [ @membership.membership_type.name ], result.pluck(:name)
      assert_not_includes result.pluck(:name), @other_membership.membership_type.name
      assert result.first.key?(:expires_at)
    end

    test "public serialization keeps the badge and removes account lifecycle fields" do
      result = SerializeUserMemberships.public_for_user(@user)

      assert_equal [ @membership.membership_type.name ], result.pluck(:name)
      assert_equal SerializeUserMemberships::PUBLIC_KEYS.sort, result.first.keys.sort
      refute result.first.key?(:expires_at)
      refute result.first.key?(:expires_label)
      refute result.first.key?(:permanent)
    end

    private

    def create_membership(user:, name:)
      type = MembershipType.create!(
        slug: "membership-#{SecureRandom.hex(4)}",
        name: name,
        duration_days: 30
      )
      UserMembership.create!(
        user: user,
        membership_type: type,
        starts_at: 1.day.ago,
        expires_at: 30.days.from_now,
        source: :admin_grant
      )
    end
  end
end
