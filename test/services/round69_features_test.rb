# frozen_string_literal: true

require "test_helper"

class Round69PmShowRestrictionsTest < ActionDispatch::IntegrationTest
  test "conversation show exposes warning restrictions" do
    sender = create_user
    recipient = create_user(username: "r69recv#{SecureRandom.hex(4)}")
    enable_forum_pm!(sender)
    enable_forum_pm!(recipient)

    result = Community::CreateConversation.call(
      sender: sender,
      recipient_username: recipient.username,
      body: "Hello"
    )
    conv = result.value[:conversation]

    sign_in_as(sender)
    get forum_conversation_path(conv)
    assert_response :success
    assert_includes response.body, "warningRestrictions"
    assert_includes response.body, "canSendPm"
  end
end

class Round69SavedSearchIntegrationTest < ActionDispatch::IntegrationTest
  test "create saved search returns url with assigned filter" do
    user = create_user
    sign_in_as(user)

    post forum_saved_searches_path, params: {
      saved_search: {
        name: "已分配",
        query: "bug",
        filters: { assigned: "assigned", category: "general" }
      }
    }, as: :json

    assert_response :created
    body = JSON.parse(response.body)
    assert_includes body["url"], "assigned=assigned"
    assert_includes body["url"], "category=general"
  end
end

class Round69StoreIndexCompareTest < ActionDispatch::IntegrationTest
  test "store index includes compare props for products" do
    user = create_user
    product = Commerce::Product.create!(
      name: "List Compare",
      slug: "r69-lc-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: :active,
      price_cents: 100,
      currency: "CNY",
      minimum_quantity: 1,
      stock: 5,
      public_id: "pub_r69lc_#{SecureRandom.hex(4)}"
    )

    sign_in_as(user)
    get store_products_path
    assert_response :success
    assert_includes response.body, "compare_url"
    assert_includes response.body, product.name
  end

  test "upcoming section includes compare props" do
    user = create_user
    product = Commerce::Product.create!(
      name: "Upcoming List",
      slug: "r69-ul-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: :active,
      price_cents: 100,
      currency: "CNY",
      minimum_quantity: 1,
      available_at: 2.days.from_now,
      public_id: "pub_r69ul_#{SecureRandom.hex(4)}"
    )

    sign_in_as(user)
    get store_products_path
    assert_response :success
    assert_includes response.body, "upcoming_products"
    assert_includes response.body, product.name
    assert_includes response.body, "compare_url"
    assert_includes response.body, "/store/compare/toggle?product_id=#{product.public_id}"
  end
end

class Round69CompareLocalStorageTest < ActiveSupport::TestCase
  test "compare page persists only diff preference key" do
    content = File.read(Rails.root.join("app/javascript/pages/Commerce/Compare/Show.vue"))
    assert_includes content, "mcweb_compare_only_diff"
    assert_includes content, "localStorage"
    assert_includes content, "onlyDiffRows"
  end
end

class Round69StoreFilterChipsTest < ActiveSupport::TestCase
  test "store index has active filter chips" do
    content = File.read(Rails.root.join("app/javascript/pages/Commerce/Products/Index.vue"))
    assert_includes content, "hasActiveFilters"
    assert_includes content, "clearFilters"
    assert_includes content, "commerce.productList.activeFilters"
  end
end
