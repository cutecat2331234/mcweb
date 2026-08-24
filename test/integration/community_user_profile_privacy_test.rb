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
    Commerce::Order.create!(
      user: @target,
      status: "cancelled",
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
    @section = Community::Section.create!(
      category: category,
      name: "Privacy section #{SecureRandom.hex(4)}",
      slug: "privacy-section-#{SecureRandom.hex(4)}"
    )
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
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

    Minecraft::IngameStatusForUser.stub(:call, ->(user:) { flunk("ordinary viewer queried private game presence for #{user.id}") }) do
      get card_forum_user_path(@target.username), as: :json
    end
    assert_response :success
    %w[last_seen_at online ingame_online ingame_server last_seen_ingame_at].each do |key|
      assert_not response.parsed_body.key?(key), "ordinary viewer card leaked #{key}"
    end
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
    assert_equal false, profile.fetch(:forum_profile_activity_public)
    assert props.fetch(:account_type).present?
    assert_includes props.fetch(:role_names), "Private role"
    assert_equal [ "Private group" ], props.fetch(:game_permission_groups).pluck(:label)
    assert props.fetch(:memberships).first.key?(:expires_at)
    assert props.dig(:minecraft, :uuid).present?
    assert_equal [ "owner field", "public field" ], props.dig(:minecraft, :fields).pluck(:label).sort

    ingame = ServiceResult.success(ingame_online: true, ingame_server: "Private Lobby")
    Minecraft::IngameStatusForUser.stub(:call, ingame) do
      get card_forum_user_path(@target.username), as: :json
    end
    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    card = response.parsed_body
    assert card.fetch("last_seen_at").present?
    assert_equal true, card.fetch("online")
    assert_equal true, card.fetch("ingame_online")
    assert_equal "Private Lobby", card.fetch("ingame_server")
    assert_public_card_membership(card)
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
    assert_equal 1, profile.fetch(:recent_point_transactions).size
    assert inertia.props.deep_symbolize_keys.fetch(:memberships).first.key?(:expires_at)
    props = inertia.props.deep_symbolize_keys
    assert_nil props[:account_type]
    assert_empty props.fetch(:role_names)
    assert_empty props.fetch(:game_permission_groups)
    assert_nil props.dig(:minecraft, :uuid)
    assert_equal [ "public field" ], props.dig(:minecraft, :fields).pluck(:label)
    refute profile.key?(:forum_profile_activity_public)

    ingame = ServiceResult.success(ingame_online: true, ingame_server: "Staff Lobby")
    Minecraft::IngameStatusForUser.stub(:call, ingame) do
      get card_forum_user_path(@target.username), as: :json
    end
    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    card = response.parsed_body
    assert card.fetch("last_seen_at").present?
    assert_equal true, card.fetch("online")
    assert_equal true, card.fetch("ingame_online")
    assert_equal "Staff Lobby", card.fetch("ingame_server")
    assert_public_card_membership(card)
  end

  test "explicit user opt in exposes only the bounded summary on all three profile surfaces" do
    @target.update!(forum_profile_activity_public: true)
    ingame = ServiceResult.success(ingame_online: true, ingame_server: "Public Lobby")

    Minecraft::IngameStatusForUser.stub(:call, ingame) do
      get card_forum_user_path(@target.username), as: :json
    end
    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    card = response.parsed_body
    assert_equal true, card.fetch("online")
    assert_equal true, card.fetch("ingame_online")
    assert_equal "Public Lobby", card.fetch("ingame_server")
    refute card.key?("last_seen_ingame_at")

    get forum_user_path(@target.username)
    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    props = inertia.props.deep_symbolize_keys
    profile = props.fetch(:profile)
    assert_equal 42, profile.fetch(:forum_points)
    assert_equal 2, profile.fetch(:check_in_streak)
    assert_equal 1, profile.fetch(:check_in_total)
    assert_equal 1, profile.fetch(:orders_count)
    assert_equal true, profile.fetch(:online)
    refute profile.key?(:recent_point_transactions)
    refute profile.key?(:profile_views)
    refute profile.key?(:trust_progress)
    refute profile.key?(:forum_pm_policy)
    refute profile.key?(:forum_profile_activity_public)
    assert_empty props.fetch(:role_names)
    assert_empty props.fetch(:game_permission_groups)
    assert_empty props.fetch(:store_orders)
    assert_nil props.dig(:minecraft, :uuid)
    assert props.dig(:minecraft, :last_seen_ingame_at).present?
    membership = props.fetch(:memberships).first
    %i[expires_at expires_label permanent].each do |key|
      refute membership.key?(key), "public activity opt-in leaked membership #{key}"
    end

    get forum_members_path(q: @target.username, sort: "purchases")
    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    props = inertia.props.deep_symbolize_keys
    assert_equal "posts", props.fetch(:sort)
    assert_equal Community::UserProfileVisibility::PUBLIC_MEMBER_SORTS, props.fetch(:availableSorts)
    assert_nil props[:onlineCount]
    member = props.fetch(:members).find { |row| row.fetch(:username) == @target.username }
    assert_equal true, member.fetch(:online)
    assert_equal 1, member.fetch(:purchases_count)

    @target.update!(forum_profile_activity_public: false)
    get card_forum_user_path(@target.username), as: :json
    assert_response :success
    %w[last_seen_at online ingame_online ingame_server].each do |key|
      assert_not response.parsed_body.key?(key), "opt-out card retained #{key}"
    end
  end

  test "the account owner can update the public activity opt in" do
    required_field = Community::UserFieldDefinition.create!(
      key: "privacy_required_#{SecureRandom.hex(3)}",
      label: "Existing required profile field",
      field_type: "text",
      visibility: "public",
      active: true,
      show_on_profile: true,
      editable_by_user: true,
      required: true,
      sort_order: 0
    )
    checkbox_field = Community::UserFieldDefinition.create!(
      key: "privacy_checkbox_#{SecureRandom.hex(3)}",
      label: "Existing checkbox profile field",
      field_type: "checkbox",
      visibility: "owner",
      active: true,
      show_on_profile: true,
      editable_by_user: true,
      required: false,
      sort_order: 1
    )
    Community::UserFieldValue.create!(
      user: @target,
      definition: required_field,
      value: "keep me"
    )
    Community::UserFieldValue.create!(
      user: @target,
      definition: checkbox_field,
      value: "1"
    )
    sign_in_as(@target)

    patch forum_user_path(@target.username), params: {
      user: { forum_profile_activity_public: true }
    }

    assert_redirected_to forum_user_path(@target.username)
    assert @target.reload.forum_profile_activity_public?
    assert_equal "keep me", required_field.values.find_by!(user: @target).value
    assert_equal "1", checkbox_field.values.find_by!(user: @target).value
  end

  test "another member cannot opt the subject in" do
    sign_in_as(create_user)

    patch forum_user_path(@target.username), params: {
      user: { forum_profile_activity_public: true }
    }

    assert_response :forbidden
    refute @target.reload.forum_profile_activity_public?
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

  test "public directory rejects every sensitive sort before it can affect rows" do
    competitor = create_directory_sort_competitor

    %w[purchases online active].each do |requested_sort|
      get forum_members_path(q: @target.username, sort: requested_sort)

      assert_response :success
      props = inertia.props.deep_symbolize_keys
      assert_equal "posts", props.fetch(:sort)
      assert_equal Community::UserProfileVisibility::PUBLIC_MEMBER_SORTS, props.fetch(:availableSorts)
      assert_nil props[:onlineCount]
      assert_equal [ competitor.username, @target.username ], props.fetch(:members).pluck(:username)
      props.fetch(:members).each do |member|
        refute member.key?(:last_seen_at)
        refute member.key?(:online)
        refute member.key?(:purchases_count)
      end
    end
  end

  test "ordinary login and self visibility do not unlock directory-wide sensitive sorts" do
    competitor = create_directory_sort_competitor
    sign_in_as(@target)

    %w[purchases online active].each do |requested_sort|
      get forum_members_path(q: @target.username, sort: requested_sort)

      assert_response :success
      props = inertia.props.deep_symbolize_keys
      assert_equal "posts", props.fetch(:sort)
      assert_equal [ competitor.username, @target.username ], props.fetch(:members).pluck(:username)
      assert_nil props[:onlineCount]
      own_row = props.fetch(:members).find { |row| row.fetch(:username) == @target.username }
      assert_equal true, own_row.fetch(:online)
      assert_equal 1, own_row.fetch(:purchases_count)
      other_row = props.fetch(:members).find { |row| row.fetch(:username) == competitor.username }
      refute other_row.key?(:online)
      refute other_row.key?(:purchases_count)
    end
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
      forum_profile_activity_public
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

  def create_directory_sort_competitor
    competitor = create_user(username: "#{@target.username}peer")
    competitor.update!(last_seen_at: 10.minutes.ago)
    topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: competitor,
      title: "Public sort baseline",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: competitor,
      replies_count: 1
    )
    2.times do |index|
      Community::Post.create!(
        topic: topic,
        user: competitor,
        floor_number: index + 1,
        body: "Public post #{index}",
        status: "published"
      )
    end
    competitor
  end
end
