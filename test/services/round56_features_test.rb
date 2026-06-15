# frozen_string_literal: true

require "test_helper"

class Community::UnassignedSearchTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @assignee = create_user
    category = Community::Category.find_or_create_by!(slug: "r56-unas-#{SecureRandom.hex(4)}") { |c| c.name = "U" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r56-unas-sec-#{SecureRandom.hex(4)}") { |s| s.name = "S"; s.position = 0 }
    result1 = Community::CreateTopic.call(user: @user, section: @section, title: "Assigned #{SecureRandom.hex(4)}", body: "OP", ip_address: "127.0.0.1")
    assert result1.success?, result1.error
    @assigned = result1.value
    @assigned.update!(assigned_to: @assignee)
    @open = Community::Topic.create!(
      section: @section,
      user: @user,
      title: "Open #{SecureRandom.hex(4)}",
      status: :published,
      last_posted_at: Time.current
    )
    Community::Post.create!(topic: @open, user: @user, body: "OP", floor_number: 1, status: :published)
  end

  test "parse is:unassigned" do
    result = Community::ParseSearchQuery.call(query: "is:unassigned help")
    assert result.success?
    assert_equal "unassigned", result.value[:assigned_filter]
  end

  test "parse assigned:me" do
    result = Community::ParseSearchQuery.call(query: "assigned:me bugs")
    assert result.success?
    assert_equal "me", result.value[:assignee_filter]
  end

  test "apply unassigned filter" do
    scope = Community::Topic.where(forum_section_id: @section.id)
    filtered = Community::ApplyTopicSearchFilters.call(scope: scope, assigned_filter: "unassigned").value
    assert_includes filtered.pluck(:id), @open.id
    assert_not_includes filtered.pluck(:id), @assigned.id
  end

  test "apply assignee filter" do
    scope = Community::Topic.where(forum_section_id: @section.id)
    filtered = Community::ApplyTopicSearchFilters.call(scope: scope, assignee_id: @assignee.id).value
    assert_equal [ @assigned.id ], filtered.pluck(:id)
  end
end

class Community::AssignedInboxTest < ActionDispatch::IntegrationTest
  setup do
    @staff = create_user
    grant_permission(@staff, "forum.topics.lock")
    @assignee = create_user
    category = Community::Category.find_or_create_by!(slug: "r56-inbox-#{SecureRandom.hex(4)}") { |c| c.name = "I" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r56-inbox-sec-#{SecureRandom.hex(4)}") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @staff, section: @section, title: "My assignment", body: "OP", ip_address: "127.0.0.1").value
    @topic.update!(assigned_to: @assignee)
    sign_in_as(@assignee)
  end

  test "assigned inbox lists topics for current user" do
    get forum_assigned_path
    assert_response :success
    assert_includes response.body, "My assignment"
  end
end

class Community::TopicFilterAssignedTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @mod = create_user
    grant_permission(@mod, "forum.topics.lock")
    category = Community::Category.find_or_create_by!(slug: "r56-filter-#{SecureRandom.hex(4)}") { |c| c.name = "F" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r56-filter-sec-#{SecureRandom.hex(4)}") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @user, section: @section, title: "Filter", body: "OP", ip_address: "127.0.0.1").value
    @topic.update!(assigned_to: @mod)
  end

  test "assigned_mine filter" do
    helper = Object.new.extend(Community::TopicFilterable)
    scope = Community::Topic.where(id: @topic.id)
    filtered = helper.send(:apply_topic_filter, scope, filter: "assigned_mine", user: @mod)
    assert_equal [ @topic.id ], filtered.pluck(:id)
  end
end

class Community::MembersTrustOverrideFilterTest < ActiveSupport::TestCase
  test "trust level filter respects override" do
    user = create_user
    user.update!(forum_trust_level_override: 3)
    controller = Community::MembersController.new
    scope = User.where(id: user.id)
    filtered = controller.send(:apply_trust_level_filter, scope, "3")
    assert_includes filtered.pluck(:id), user.id
  end
end

class Commerce::StoreLatestRssTest < ActionDispatch::IntegrationTest
  setup do
    Commerce::Product.create!(
      public_id: "prod_r56_#{SecureRandom.hex(4)}",
      name: "Latest RSS Product",
      slug: "latest-rss-#{SecureRandom.hex(4)}",
      price_cents: 1000,
      currency: "CNY",
      status: "active",
      product_type: "virtual"
    )
  end

  test "store latest rss renders" do
    get store_latest_rss_path, as: :rss
    assert_response :success
    assert_includes response.body, "Latest RSS Product"
  end
end

class Commerce::ShippingAddressUpdateTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @address = Commerce::ShippingAddress.create!(
      user: @user,
      name: "张三",
      phone: "13800000000",
      line1: "路 1 号",
      city: "上海",
      province: "上海"
    )
  end

  test "upsert updates existing address" do
    result = Commerce::UpsertShippingAddress.call(
      user: @user,
      address: @address,
      params: { name: "李四", phone: "13900000000", line1: "路 2 号", city: "北京", province: "北京" }
    )
    assert result.success?
    assert_equal "李四", @address.reload.name
  end
end

class Community::StaffMentionSearchTest < ActionDispatch::IntegrationTest
  setup do
    @mod = create_user(username: "staffmod#{SecureRandom.hex(3)}")
    grant_permission(@mod, "forum.topics.lock")
    @viewer = create_user
    sign_in_as(@viewer)
    grant_permission(@viewer, "forum.topics.lock")
  end

  test "staff mention search returns moderators" do
    get forum_mention_search_path, params: { q: @mod.username[0..4], staff: "1" }, as: :json
    assert_response :success
    data = JSON.parse(response.body)
    assert data["users"].any? { |u| u["username"] == @mod.username }
  end
end
