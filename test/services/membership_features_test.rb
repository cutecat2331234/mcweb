# frozen_string_literal: true

require "test_helper"

class Commerce::MembershipFeaturesTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @other = create_user(email: "other-#{SecureRandom.hex(4)}@example.com", username: "other#{SecureRandom.hex(3)}")

    @membership_type = Commerce::MembershipType.create!(
      slug: "vip-#{SecureRandom.hex(3)}",
      name: "VIP",
      duration_mode: "fixed_days",
      duration_days: 30,
      luckperms_group: "vip",
      game_permission_enabled: false
    )

    @prerequisite_product = Commerce::Product.create!(
      name: "Base Pass",
      slug: "base-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 1000,
      currency: "CNY",
      fulfillment_config: { entitlement_days: 30 }
    )

    @membership_product = Commerce::Product.create!(
      name: "VIP Monthly",
      slug: "vip-prod-#{SecureRandom.hex(4)}",
      product_type: "membership",
      status: "active",
      price_cents: 3000,
      currency: "CNY",
      membership_type: @membership_type,
      fulfillment_config: {},
      prerequisite_match_mode: "all"
    )

    @gated_product = Commerce::Product.create!(
      name: "Gated Item",
      slug: "gated-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 500,
      currency: "CNY",
      fulfillment_config: {},
      prerequisite_match_mode: "all"
    )

    Commerce::ProductPrerequisite.create!(
      product: @gated_product,
      required_product: @prerequisite_product,
      requirement_mode: "ever_purchased"
    )
  end

  test "check prerequisites fails for guest" do
    result = Commerce::CheckProductPrerequisites.call(user: nil, product: @gated_product)
    assert result.failure?
  end

  test "check prerequisites ever_purchased" do
    result = Commerce::CheckProductPrerequisites.call(user: @user, product: @gated_product)
    assert result.failure?

    create_paid_order!(user: @user, product: @prerequisite_product)

    result = Commerce::CheckProductPrerequisites.call(user: @user, product: @gated_product)
    assert result.success?
  end

  test "check prerequisites active entitlement" do
    @gated_product.prerequisites.first.update!(requirement_mode: "active")

    result = Commerce::CheckProductPrerequisites.call(user: @user, product: @gated_product)
    assert result.failure?

    order = create_paid_order!(user: @user, product: @prerequisite_product)
    Commerce::GrantProductEntitlement.call(order_item: order.items.first)

    result = Commerce::CheckProductPrerequisites.call(user: @user, product: @gated_product)
    assert result.success?
  end

  test "prerequisite match any" do
    @gated_product.update!(prerequisite_match_mode: "any")
    Commerce::ProductPrerequisite.create!(
      product: @gated_product,
      required_product: @membership_product,
      requirement_mode: "ever_purchased"
    )

    result = Commerce::CheckProductPrerequisites.call(user: @user, product: @gated_product)
    assert result.failure?

    create_paid_order!(user: @user, product: @membership_product)
    result = Commerce::CheckProductPrerequisites.call(user: @user, product: @gated_product)
    assert result.success?
  end

  test "grant membership stacks expiry window" do
    first = Commerce::GrantMembership.call(
      user: @user,
      membership_type: @membership_type,
      grant_game_permissions: false
    )
    assert first.success?

    travel 5.days do
      second = Commerce::GrantMembership.call(
        user: @user,
        membership_type: @membership_type,
        grant_game_permissions: false
      )
      assert second.success?
      assert second.value.starts_at > Time.current
      assert second.value.expires_at > first.value.expires_at
    end
  end

  test "fulfill membership item is idempotent" do
    order = create_paid_order!(user: @user, product: @membership_product)
    item = order.items.first

    result = Commerce::FulfillMembershipItem.call(order_item: item)
    assert result.success?

    again = Commerce::FulfillMembershipItem.call(order_item: item)
    assert again.success?
    assert_equal 1, Commerce::UserMembership.where(source_order_item_id: item.id).count
  end

  test "revoke memberships for order on refund path" do
    order = create_paid_order!(user: @user, product: @membership_product)
    Commerce::FulfillMembershipItem.call(order_item: order.items.first)
    assert_equal 1, Commerce::UserMembership.active.count

    result = Commerce::RevokeMembershipsForOrder.call(order: order)
    assert result.success?
    assert_equal 1, result.value[:revoked]
    assert_equal 0, Commerce::UserMembership.active.count
  end

  test "revoke membership skips permission revoke when another active membership remains" do
    Minecraft::Server.create!(
      public_id: "srv_#{SecureRandom.hex(4)}",
      name: "Membership Server",
      address: "127.0.0.1",
      port: 25565,
      status: "online"
    )
    profile = Minecraft::PlayerProfile.create!
    Minecraft::PlayerIdentity.create!(
      player_profile: profile,
      platform: "java",
      external_uuid: SecureRandom.uuid,
      username: "MemberUser",
      valid_from: Time.current
    )
    Minecraft::IdentityLink.create!(user: @user, player_profile: profile, linked_at: Time.current)

    @membership_type.update!(game_permission_enabled: true, grant_commands: [ "lp user {player} parent set vip" ])

    first_order = create_paid_order!(user: @user, product: @membership_product)
    first_item = first_order.items.first
    Commerce::FulfillMembershipItem.call(order_item: first_item)
    first_membership = Commerce::UserMembership.find_by!(source_order_item_id: first_item.id)

    Commerce::UserMembership.create!(
      user: @user,
      membership_type: @membership_type,
      status: :active,
      starts_at: 1.day.ago,
      expires_at: 60.days.from_now,
      source: :admin_grant
    )

    assert_no_difference -> { Minecraft::ConnectorTask.count } do
      result = Commerce::RevokeMembership.call(membership: first_membership)
      assert result.success?
    end

    assert_equal 1, Commerce::UserMembership.currently_active.where(user: @user).count
  end

  test "expire memberships job marks expired and revokes when no overlap" do
    membership = Commerce::GrantMembership.call(
      user: @user,
      membership_type: @membership_type,
      grant_game_permissions: false
    ).value
    membership.update!(expires_at: 1.hour.ago)

    Commerce::ExpireMembershipsJob.perform_now
    membership.reload
    assert membership.expired?
  end

  test "lookup player includes membership fields" do
    Commerce::GrantMembership.call(user: @user, membership_type: @membership_type, grant_game_permissions: false)
    profile = Minecraft::PlayerProfile.create!
    Minecraft::PlayerIdentity.create!(
      player_profile: profile,
      platform: "java",
      external_uuid: SecureRandom.uuid,
      username: "Steve",
      valid_from: Time.current
    )
    Minecraft::IdentityLink.create!(user: @user, player_profile: profile, linked_at: Time.current)

    result = Minecraft::LookupPlayer.call(uuid: profile.active_identity.external_uuid, username: "Steve")
    assert result.success?
    assert result.value[:membership_labels].include?("VIP")
    assert result.value[:whois_lines].any? { |line| line.include?("VIP") }
  end

  private

  def create_paid_order!(user:, product:)
    cart = Commerce::Cart.create!(user: user)
    cart.add_item!(product: product, quantity: 1)
    order_result = Commerce::CreateOrder.call(cart: cart.reload, user: user)
    assert order_result.success?, order_result.error
    order = order_result.value
    order.update!(status: "paid")
    order
  end
end
