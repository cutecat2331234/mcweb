# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

class CommunityUserProfilePrivacyTest < ActionDispatch::IntegrationTest
  PRIVATE_PERMISSION = Community::UserProfileVisibility::PRIVATE_ACTIVITY_PERMISSION

  setup do
    @target = create_user(username: "privacy#{SecureRandom.hex(4)}")
    @target.update_column(:last_seen_at, 1.minute.ago)
    @point_account = Community::PointAccount.create!(user: @target, currency: "points", balance: 42)
    Community::PointTransaction.create!(
      account: @point_account,
      user: @target,
      currency: "points",
      reason: "privacy_test",
      amount: 42,
      balance_after: 42
    )
    Community::CheckIn.create!(
      user: @target,
      checked_on: Date.current,
      streak: 2,
      points_awarded: 1
    )
    Commerce::Order.create!(
      user: @target,
      status: "paid",
      subtotal_cents: 100,
      discount_cents: 0,
      total_cents: 100,
      currency: "CNY"
    )
    membership_type = Commerce::MembershipType.create!(
      slug: "privacy-#{SecureRandom.hex(4)}",
      name: "Private expiry",
      duration_days: 30
    )
    Commerce::UserMembership.create!(
      user: @target,
      membership_type: membership_type,
      starts_at: 1.day.ago,
      expires_at: 30.days.from_now,
      source: :admin_grant
    )
    @player_profile = Minecraft::PlayerProfile.create!
    @player_identity = Minecraft::PlayerIdentity.create!(
      player_profile: @player_profile,
      platform: "java",
      external_uuid: SecureRandom.uuid,
      username: "PrivacyPlayer",
      identity_type: "java",
      valid_from: Time.current,
      last_seen_ingame_at: 2.minutes.ago
    )
    Minecraft::IdentityLink.create!(
      user: @target,
      player_profile: @player_profile,
      linked_at: Time.current
    )
    Minecraft::PermissionGroup.create!(
      player_profile: @player_profile,
      group_key: "private_group",
      group_label: "Private group",
      source: "test"
    )
    internal_role = Role.create!(
      key: "private_role_#{SecureRandom.hex(4)}",
      name: "Private role"
    )
    @target.roles << internal_role
    grant_admin_module(@target, "forum")
    category = Community::Category.create!(
      name: "Privacy category #{SecureRandom.hex(4)}",
      slug: "privacy-category-#{SecureRandom.hex(4)}"
    )
    section = Community::Section.create!(
      category: category,
      name: "Privacy section #{SecureRandom.hex(4)}",
      slug: "privacy-section-#{SecureRandom.hex(4)}"
    )
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @target,
      title: "Private author activity",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @target,
      replies_count: 0
    )
    @post = Community::Post.create!(
      topic: @topic,
      user: @target,
      floor_number: 1,
      body: "Private author points must follow the viewer policy",
      status: "published"
    )
    %w[public owner staff].each do |visibility|
      definition = Minecraft::ProfileFieldDefinition.create!(
        key: "privacy_#{visibility}_#{SecureRandom.hex(3)}",
        label: "#{visibility} field",
        visibility: visibility
      )
      Minecraft::ProfileFieldValue.create!(
        player_profile: @player_profile,
        field_key: definition.key,
        value: "#{visibility} value"
      )
    end
  end

  test "anonymous card and profile omit private activity" do
    Minecraft::IngameStatusForUser.stub(:call, ->(user:) { flunk("public card queried private game presence for #{user.id}") }) do
      get card_forum_user_path(@target.username), as: :json
    end

    assert_response :success
    card = response.parsed_body
    %w[last_seen_at online ingame_online ingame_server last_seen_ingame_at].each do |key|
      assert_not card.key?(key), "public card leaked #{key}"
    end
    assert_public_card_membership(card)

    get forum_user_path(@target.username)
    assert_response :success
    props = inertia.props.deep_symbolize_keys
    assert_private_profile_activity_hidden(props)
  end

  test "another signed-in member cannot inspect private activity" do
    sign_in_as(create_user)

    get forum_user_path(@target.username)
    assert_response :success
    assert_private_profile_activity_hidden(inertia.props.deep_symbolize_keys)
  end

  test "a member can see their own private activity" do
    sign_in_as(@target)

    get forum_user_path(@target.username)
    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    props = inertia.props.deep_symbolize_keys
    profile = props.fetch(:profile)
    assert_equal 42, profile.fetch(:forum_points)
    assert_equal 1, profile.fetch(:orders_count)
    assert_equal 1, profile.fetch(:check_in_total)
    assert_equal true, profile.fetch(:online)
    assert_equal 1, profile.fetch(:recent_point_transactions).size
    assert props.fetch(:account_type).present?
    assert_includes props.fetch(:role_names), "Private role"
    assert_equal [ "Private group" ], props.fetch(:game_permission_groups).pluck(:label)
    assert props.fetch(:memberships).first.key?(:expires_at)
    assert props.dig(:minecraft, :uuid).present?
    assert_equal [ "owner field", "public field" ], props.dig(:minecraft, :fields).pluck(:label).sort

    get card_forum_user_path(@target.username), as: :json
    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_public_card_membership(response.parsed_body)
  end

  test "explicitly authorized staff can inspect private activity" do
    staff = create_user
    grant_permission(staff, PRIVATE_PERMISSION)
    sign_in_as(staff)

    get forum_user_path(@target.username)
    assert_response :success
    profile = inertia.props.deep_symbolize_keys.fetch(:profile)
    assert_equal 42, profile.fetch(:forum_points)
    assert_equal 1, profile.fetch(:orders_count)
    assert_equal true, profile.fetch(:online)
    assert inertia.props.deep_symbolize_keys.fetch(:memberships).first.key?(:expires_at)
    props = inertia.props.deep_symbolize_keys
    assert_nil props[:account_type]
    assert_empty props.fetch(:role_names)
    assert_empty props.fetch(:game_permission_groups)
    assert_nil props.dig(:minecraft, :uuid)
    assert_equal [ "public field" ], props.dig(:minecraft, :fields).pluck(:label)

    get card_forum_user_path(@target.username), as: :json
    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_public_card_membership(response.parsed_body)
  end

  test "minecraft staff fields use the dedicated player-view permission" do
    staff = create_user
    grant_permission(staff, "minecraft.players.view")
    sign_in_as(staff)

    get forum_user_path(@target.username)

    assert_response :success
    minecraft = inertia.props.deep_symbolize_keys.fetch(:minecraft)
    assert minecraft.fetch(:uuid).present?
    assert_equal [ "owner field", "public field", "staff field" ], minecraft.fetch(:fields).pluck(:label).sort
    assert_nil minecraft[:last_seen_ingame_at]
    assert_equal [ "Private group" ], inertia.props.deep_symbolize_keys.fetch(:game_permission_groups).pluck(:label)
    assert_nil inertia.props.deep_symbolize_keys[:account_type]
    assert_empty inertia.props.deep_symbolize_keys.fetch(:role_names)
  end

  test "role assignments use the permission explanation boundary" do
    staff = create_user
    grant_permission(staff, "identity.permissions.explain")
    sign_in_as(staff)

    get forum_user_path(@target.username)

    assert_response :success
    props = inertia.props.deep_symbolize_keys
    assert_nil props[:account_type]
    assert_includes props.fetch(:role_names), "Private role"
    assert_empty props.fetch(:game_permission_groups)
    assert_nil props.dig(:profile, :forum_points)

    get forum_staff_path
    assert_response :success
    staff_row = inertia.props.deep_symbolize_keys.fetch(:staff).find { |row| row.fetch(:username) == @target.username }
    assert_not_empty staff_row.fetch(:modules)
  end

  test "account type uses the established user detail boundary" do
    staff = create_user
    grant_permission(staff, "system.settings.manage")
    sign_in_as(staff)

    get forum_user_path(@target.username)

    assert_response :success
    props = inertia.props.deep_symbolize_keys
    assert props.fetch(:account_type).present?
    assert_empty props.fetch(:role_names)
    assert_empty props.fetch(:game_permission_groups)
    assert_nil props.dig(:profile, :forum_points)
  end

  test "role catalog read alone does not reveal per-user assignments" do
    staff = create_user
    grant_permission(staff, "identity.roles.read")
    sign_in_as(staff)

    get forum_user_path(@target.username)

    assert_response :success
    props = inertia.props.deep_symbolize_keys
    assert_nil props[:account_type]
    assert_empty props.fetch(:role_names)
    assert_empty props.fetch(:game_permission_groups)
  end

  test "public directory rejects sensitive sorting and omits sensitive fields" do
    get forum_members_path(q: @target.username, sort: "purchases")

    assert_response :success
    props = inertia.props.deep_symbolize_keys
    assert_equal "posts", props.fetch(:sort)
    assert_equal Community::UserProfileVisibility::PUBLIC_MEMBER_SORTS, props.fetch(:availableSorts)
    assert_nil props[:onlineCount]
    member = props.fetch(:members).find { |row| row.fetch(:username) == @target.username }
    assert member
    refute member.key?(:last_seen_at)
    refute member.key?(:online)
    refute member.key?(:purchases_count)
  end

  test "private directory sorting requires the dedicated permission" do
    staff = create_user
    grant_permission(staff, PRIVATE_PERMISSION)
    sign_in_as(staff)

    get forum_members_path(q: @target.username, sort: "purchases")

    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    props = inertia.props.deep_symbolize_keys
    assert_equal "purchases", props.fetch(:sort)
    assert_includes props.fetch(:availableSorts), "online"
    assert_includes props.fetch(:availableSorts), "purchases"
    assert_kind_of Integer, props.fetch(:onlineCount)
    member = props.fetch(:members).find { |row| row.fetch(:username) == @target.username }
    assert_equal 1, member.fetch(:purchases_count)
    assert_equal true, member.fetch(:online)

    get forum_members_path(q: @target.username)
    assert_response :success
    assert_equal "active", inertia.props.deep_symbolize_keys.fetch(:sort)
  end

  test "public forum index and staff directory omit private presence" do
    get forum_sections_path

    assert_response :success
    props = inertia.props.deep_symbolize_keys
    refute props.fetch(:forumStats).key?(:online)
    refute props.fetch(:forumStats).key?(:online_peak)
    assert_empty props.fetch(:staffOnline)

    get forum_staff_path

    assert_response :success
    staff = inertia.props.deep_symbolize_keys.fetch(:staff).find { |row| row.fetch(:username) == @target.username }
    assert staff
    assert_empty staff.fetch(:modules)
    refute staff.key?(:online)
    refute staff.key?(:last_seen_at)
  end

  test "private activity permission reveals presence on forum-owned surfaces" do
    viewer = create_user
    grant_permission(viewer, PRIVATE_PERMISSION)
    sign_in_as(viewer)

    get forum_sections_path

    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    props = inertia.props.deep_symbolize_keys
    assert_kind_of Integer, props.dig(:forumStats, :online)
    assert props.dig(:forumStats, :online_peak).key?(:count)
    assert_includes props.fetch(:staffOnline).pluck(:username), @target.username

    get forum_staff_path

    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    staff = inertia.props.deep_symbolize_keys.fetch(:staff).find { |row| row.fetch(:username) == @target.username }
    assert_empty staff.fetch(:modules)
    assert_equal true, staff.fetch(:online)
    assert staff.key?(:last_seen_at)
  end

  test "topic author points are omitted for guests and ordinary members" do
    get forum_topic_path(@topic)

    assert_response :success
    post = inertia.props.deep_symbolize_keys.fetch(:posts).find { |row| row.fetch(:id) == @post.id }
    refute post.key?(:author_forum_points)

    sign_in_as(create_user)
    get forum_topic_path(@topic)

    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    post = inertia.props.deep_symbolize_keys.fetch(:posts).find { |row| row.fetch(:id) == @post.id }
    refute post.key?(:author_forum_points)
  end

  test "topic author and explicitly authorized viewer can see author points" do
    sign_in_as(@target)
    get forum_topic_path(@topic)

    assert_response :success
    post = inertia.props.deep_symbolize_keys.fetch(:posts).find { |row| row.fetch(:id) == @post.id }
    assert_equal 42, post.fetch(:author_forum_points)

    viewer = create_user
    grant_permission(viewer, PRIVATE_PERMISSION)
    sign_in_as(viewer)
    get forum_topic_path(@topic)

    assert_response :success
    post = inertia.props.deep_symbolize_keys.fetch(:posts).find { |row| row.fetch(:id) == @post.id }
    assert_equal 42, post.fetch(:author_forum_points)
  end

  private

  def assert_public_card_membership(card)
    membership = card.fetch("memberships").first
    refute membership.key?("expires_at")
    refute membership.key?("expires_label")
    refute membership.key?("permanent")
  end

  def assert_private_profile_activity_hidden(props)
    profile = props.fetch(:profile)
    %i[
      forum_points recent_point_transactions check_in_streak check_in_total
      last_seen_at online profile_views orders_count trust_progress forum_pm_policy
    ].each do |key|
      refute profile.key?(key), "public profile leaked #{key}"
    end
    assert_nil props[:account_type]
    assert_empty props.fetch(:role_names)
    assert_empty props.fetch(:game_permission_groups)
    assert_nil props.dig(:minecraft, :last_seen_ingame_at)
    assert_nil props.dig(:minecraft, :uuid)
    assert_equal [ "public field" ], props.dig(:minecraft, :fields).pluck(:label)
    refute props.fetch(:memberships).first.key?(:expires_at)
    refute props.fetch(:memberships).first.key?(:expires_label)
  end
end
