# frozen_string_literal: true

require "test_helper"

class Community::TopicAssignTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @mod = create_user
    grant_permission(@mod, "forum.topics.lock")
    @assignee = create_user
    category = Community::Category.find_or_create_by!(slug: "r55-assign-#{SecureRandom.hex(4)}") { |c| c.name = "A" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r55-assign-sec-#{SecureRandom.hex(4)}") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @mod, section: @section, title: "Assign me", body: "OP", ip_address: "127.0.0.1").value
  end

  test "moderator can assign topic to staff" do
    result = Community::ModerateTopic.call(
      user: @mod,
      topic: @topic,
      action: "assign",
      assignee_username: @assignee.username
    )
    assert result.success?
    assert_equal @assignee.id, @topic.reload.assigned_to_id
  end

  test "assign notifies assignee" do
    NotificationPreference.set!(@assignee, channel: "in_app", notification_type: "forum.topic_assigned", enabled: true)
    assert_difference -> { Notification.where(user: @assignee, notification_type: "forum.topic_assigned").count }, 1 do
      Community::ModerateTopic.call(user: @mod, topic: @topic, action: "assign", assignee_username: @assignee.username)
    end
  end

  test "unassign clears assignee" do
    @topic.update!(assigned_to: @assignee)
    result = Community::ModerateTopic.call(user: @mod, topic: @topic, action: "unassign")
    assert result.success?
    assert_nil @topic.reload.assigned_to_id
  end
end

class Community::ExportTopicPostsTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r55-export-#{SecureRandom.hex(4)}") { |c| c.name = "E" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r55-export-sec-#{SecureRandom.hex(4)}") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @user, section: @section, title: "Export", body: "First post", ip_address: "127.0.0.1").value
    Community::CreatePost.call(user: @user, topic: @topic, body: "Second post", ip_address: "127.0.0.1", skip_interval_check: true)
  end

  test "exports published posts as csv" do
    result = Community::ExportTopicPosts.call(topic: @topic)
    assert result.success?
    assert_includes result.value[:csv], "First post"
    assert_includes result.value[:csv], "Second post"
    assert_includes result.value[:csv], @user.username
  end
end

class Community::AssignedSearchTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @assignee = create_user
    category = Community::Category.find_or_create_by!(slug: "r55-search-#{SecureRandom.hex(4)}") { |c| c.name = "S" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r55-search-sec-#{SecureRandom.hex(4)}") { |s| s.name = "S"; s.position = 0 }
    @assigned = Community::CreateTopic.call(user: @user, section: @section, title: "Assigned topic", body: "OP", ip_address: "127.0.0.1").value
    @assigned.update!(assigned_to: @assignee)
    Community::CreateTopic.call(user: @user, section: @section, title: "Unassigned topic", body: "OP", ip_address: "127.0.0.1")
  end

  test "parse search query is:assigned" do
    result = Community::ParseSearchQuery.call(query: "is:assigned bugs")
    assert result.success?
    assert_equal "assigned", result.value[:assigned_filter]
    assert_equal "bugs", result.value[:query]
  end

  test "apply assigned filter" do
    scope = Community::Topic.where(forum_section_id: @section.id)
    filtered = Community::ApplyTopicSearchFilters.call(scope: scope, assigned_filter: "assigned").value
    assert_equal [ @assigned.id ], filtered.pluck(:id)
  end
end

class Community::TrustLevelOverrideTest < ActiveSupport::TestCase
  test "manual override takes precedence" do
    user = create_user
    user.update!(forum_trust_level_override: 3)
    assert_equal 3, Community::TrustLevel.level_for(user)
  end

  test "invalid override ignored" do
    user = create_user
    user.update!(forum_trust_level_override: 99)
    assert_equal 0, Community::TrustLevel.level_for(user)
  end
end

class Commerce::ShippingAddressTest < ActiveSupport::TestCase
  setup do
    @user = create_user
  end

  test "upsert creates address" do
    result = Commerce::UpsertShippingAddress.call(
      user: @user,
      params: {
        label: "家",
        name: "张三",
        phone: "13800000000",
        line1: "测试路 1 号",
        city: "上海",
        province: "上海"
      },
      make_default: true
    )
    assert result.success?
    assert_equal 1, @user.shipping_addresses.count
    assert @user.shipping_addresses.first.default_address?
  end
end

class Commerce::StoreCategoryRssTest < ActionDispatch::IntegrationTest
  setup do
    @category = Commerce::Category.find_or_create_by!(slug: "r55-store-rss-#{SecureRandom.hex(4)}") { |c| c.name = "RSS" }
    Commerce::Product.create!(
      public_id: "prod_r55_#{SecureRandom.hex(4)}",
      name: "RSS Product",
      slug: "rss-product-#{SecureRandom.hex(4)}",
      price_cents: 1000,
      currency: "CNY",
      status: "active",
      category: @category,
      product_type: "virtual"
    )
  end

  test "store category rss renders" do
    get store_category_rss_path(slug: @category.slug), as: :rss
    assert_response :success
    assert_includes response.body, "RSS Product"
  end
end

class Commerce::CartGiftNoteTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @cart = Commerce::Cart.find_or_create_by!(user: @user)
    @product = Commerce::Product.create!(
      public_id: "prod_gift_#{SecureRandom.hex(4)}",
      name: "Gift item",
      slug: "gift-item-#{SecureRandom.hex(4)}",
      price_cents: 500,
      currency: "CNY",
      status: "active",
      product_type: "virtual"
    )
    @item = @cart.add_item!(product: @product, quantity: 1)
  end

  test "cart item stores gift note" do
    @item.update!(gift_note: "生日快乐")
    order_result = Commerce::CreateOrder.call(cart: @cart, user: @user)
    assert order_result.success?
    item = order_result.value.items.first
    assert_equal "生日快乐", item.fulfillment_snapshot["gift_note"]
  end
end

class Community::TopicExportIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @mod = create_user
    grant_permission(@mod, "forum.topics.lock")
    category = Community::Category.find_or_create_by!(slug: "r55-exp-int-#{SecureRandom.hex(4)}") { |c| c.name = "E" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r55-exp-int-sec-#{SecureRandom.hex(4)}") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @mod, section: @section, title: "CSV", body: "Export me", ip_address: "127.0.0.1").value
    sign_in_as(@mod)
  end

  test "moderator can export topic csv" do
    get export_forum_topic_path(@topic, format: :csv)
    assert_response :success
    assert_includes response.body, "Export me"
    assert_match(/text\/csv/, response.media_type)
  end
end

class Commerce::ShippingAddressesIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    enable_store_feature!(:shipping)
    @user = create_user
    sign_in_as(@user)
  end

  test "shipping addresses index" do
    get store_shipping_addresses_path
    assert_response :success
  end

  test "create shipping address" do
    assert_difference -> { Commerce::ShippingAddress.count }, 1 do
      post store_shipping_addresses_path, params: {
        address: {
          name: "李四",
          phone: "13900000000",
          line1: "路 2 号",
          city: "北京",
          province: "北京"
        },
        make_default: "1"
      }
    end
    assert_redirected_to store_shipping_addresses_path
  end
end
