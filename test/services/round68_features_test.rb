# frozen_string_literal: true

require "test_helper"

class Round68WishlistFilterPresetTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    sign_in_as(@user)
  end

  test "creates wishlist filter preset with url" do
    post store_wishlist_filter_presets_path, params: {
      wishlist_filter_preset: {
        name: "有货促销",
        filters: { in_stock: true, on_sale: true, sort: "price_asc" }
      }
    }, as: :json

    assert_response :created
    body = JSON.parse(response.body)
    assert_includes body["url"], "in_stock=1"
    assert_includes body["url"], "on_sale=1"
    assert_includes body["url"], "sort=price_asc"
  end

  test "wishlist index exposes saved filter presets" do
    Commerce::WishlistFilterPreset.create!(
      user: @user,
      name: "即将上架",
      filters: { coming_soon: true }
    )

    get store_wishlist_path
    assert_response :success
    assert_includes response.body, "savedFilterPresets"
    assert_includes response.body, "saveFilterPresetUrl"
  end
end

class Round68PreviewCompareTest < ActionDispatch::IntegrationTest
  test "preview page exposes compare props for upcoming product" do
    user = create_user
    product = Commerce::Product.create!(
      name: "Upcoming Compare",
      slug: "r68-up-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: :active,
      price_cents: 100,
      currency: "CNY",
      minimum_quantity: 1,
      available_at: 2.days.from_now,
      public_id: "pub_r68up_#{SecureRandom.hex(4)}"
    )

    sign_in_as(user)
    get preview_store_product_path(product)
    assert_response :success
    assert_includes response.body, "compareUrl"
    assert_includes response.body, "compared"
  end

  test "toggle compare accepts coming soon product" do
    user = create_user
    product = Commerce::Product.create!(
      name: "Compare Soon",
      slug: "r68-cs-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: :active,
      price_cents: 100,
      currency: "CNY",
      minimum_quantity: 1,
      available_at: 2.days.from_now,
      public_id: "pub_r68cs_#{SecureRandom.hex(4)}"
    )

    sign_in_as(user)
    post store_toggle_compare_path(product_id: product.public_id)
    assert_redirected_to preview_store_product_path(product)

    follow_redirect!
    get store_compare_path
    assert_response :success
    assert_includes response.body, product.name
  end
end

class Round68GroupPmLinkTest < ActiveSupport::TestCase
  test "create group conversation rejects warned user sending links" do
    sender = create_user
    recipient = create_user(username: "r68grp#{SecureRandom.hex(4)}")
    enable_forum_pm!(sender)
    SiteSetting.set("forum.warning_block_links_threshold", "1")
    Community::UserWarning.create!(user: sender, issuer: sender, reason: "test", points: 5)

    result = Community::CreateGroupConversation.call(
      sender: sender,
      title: "Test Group",
      recipient_usernames: recipient.username,
      body: "See https://example.com"
    )
    assert result.failure?
    assert_match(/链接/, result.error)
  end

  test "send message rejects warned user sending links" do
    sender = create_user
    recipient = create_user(username: "r68recv#{SecureRandom.hex(4)}")
    enable_forum_pm!(sender)
    enable_forum_pm!(recipient)
    SiteSetting.set("forum.warning_block_links_threshold", "1")
    Community::UserWarning.create!(user: sender, issuer: sender, reason: "test", points: 5)

    conv = Community::CreateGroupConversation.call(
      sender: recipient,
      title: "Existing",
      recipient_usernames: sender.username,
      body: "Hello group"
    ).value[:conversation]

    result = Community::SendMessage.call(user: sender, conversation: conv, body: "Link https://example.com")
    assert result.failure?
    assert_match(/链接/, result.error)
  end
end

class Round68SavedSearchUrlTest < ActiveSupport::TestCase
  test "saved search url includes assigned filter" do
    user = create_user
    search = Community::SavedSearch.create!(
      user: user,
      name: "Assigned",
      query: "test",
      filters: { assigned: "assigned", category: "general" }
    )

    controller = Community::SavedSearchesController.new
    params = controller.send(:search_url_params, search)
    assert_equal "assigned", params[:assigned]
    assert_equal "general", params[:category]
  end
end

class Round68CompareDiffToggleTest < ActiveSupport::TestCase
  test "compare page includes only diff rows toggle" do
    content = File.read(Rails.root.join("app/javascript/pages/Commerce/Compare/Show.vue"))
    assert_includes content, "onlyDiffRows"
    assert_includes content, "visibleRows"
    assert_includes content, "仅差异行"
  end
end

class Round68CategorySortTest < ActionDispatch::IntegrationTest
  test "category page passes sort filter" do
    category = Commerce::Category.create!(name: "R68 Cat", slug: "r68-cat-#{SecureRandom.hex(4)}")
    get store_category_path(category.slug), params: { sort: "price_asc" }
    assert_response :success
    assert_includes response.body, '"sort":"price_asc"'
  end
end
