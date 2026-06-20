# frozen_string_literal: true

require "test_helper"

class Round70SearchPostPaginationTest < ActiveSupport::TestCase
  test "search page uses post_page param for post pagination" do
    content = File.read(Rails.root.join("app/javascript/pages/Community/Search/Index.vue"))
    assert_includes content, 'page-param="post_page"'
    assert_not_includes content, 'query-param="post_page"'
  end

  test "search page saves advanced filters" do
    content = File.read(Rails.root.join("app/javascript/pages/Community/Search/Index.vue"))
    assert_includes content, "locked:"
    assert_includes content, "poll:"
    assert_includes content, "assigned:"
  end
end

class Round70StoreWishlistListTest < ActionDispatch::IntegrationTest
  test "store index includes wishlist props for products" do
    user = create_user
    product = Commerce::Product.create!(
      name: "Wishlist List",
      slug: "r70-wl-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: :active,
      price_cents: 100,
      currency: "CNY",
      minimum_quantity: 1,
      stock: 5,
      public_id: "pub_r70wl_#{SecureRandom.hex(4)}"
    )

    sign_in_as(user)
    get store_products_path
    assert_response :success
    assert_includes response.body, "wishlist_url"
    assert_includes response.body, product.name
  end

  test "toggle wishlist from store index" do
    user = create_user
    product = Commerce::Product.create!(
      name: "Toggle WL",
      slug: "r70-tw-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: :active,
      price_cents: 100,
      currency: "CNY",
      minimum_quantity: 1,
      stock: 5,
      public_id: "pub_r70tw_#{SecureRandom.hex(4)}"
    )

    sign_in_as(user)
    post wishlist_store_product_path(product), headers: { "HTTP_REFERER" => store_products_url }
    assert Commerce::WishlistItem.exists?(user: user, product: product)
  end
end

class Round70AddParticipantValidationTest < ActionDispatch::IntegrationTest
  test "cannot add silenced user to group conversation" do
    actor = create_user
    silenced = create_user(username: "r70sil#{SecureRandom.hex(4)}")
    grant_permission(actor, "forum.users.mute")
    enable_forum_pm!(actor)
    enable_forum_pm!(silenced)

    Community::CreateUserSilence.call(actor: actor, user: silenced, reason: "Test", days: 1)

    result = Community::CreateGroupConversation.call(
      sender: actor,
      title: "R70 Group",
      recipient_usernames: [ create_user(username: "r70m#{SecureRandom.hex(3)}").username ],
      body: "Hi"
    )
    conv = result.value[:conversation]

    add = Community::AddConversationParticipant.call(
      actor: actor,
      conversation: conv,
      username: silenced.username
    )
    assert add.failure?
    assert_includes add.error.to_s, "禁言"
  end

  test "cannot add user without pm permission" do
    actor = create_user
    newbie = create_user(username: "r70new#{SecureRandom.hex(4)}")
    enable_forum_pm!(actor)

    result = Community::CreateGroupConversation.call(
      sender: actor,
      title: "R70 Group2",
      recipient_usernames: [ create_user(username: "r70m2#{SecureRandom.hex(3)}").username ],
      body: "Hi"
    )
    conv = result.value[:conversation]

    add = Community::AddConversationParticipant.call(
      actor: actor,
      conversation: conv,
      username: newbie.username
    )
    assert add.failure?
    assert_includes add.error.to_s, "私信"
  end
end

class Round70PublicWishlistFilterTest < ActionDispatch::IntegrationTest
  test "public wishlist respects filter params" do
    owner = create_user
    Commerce::EnsureWishlistShareToken.call(user: owner)
    owner.reload

    in_stock = Commerce::Product.create!(
      name: "In Stock WL",
      slug: "r70-is-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: :active,
      price_cents: 100,
      currency: "CNY",
      minimum_quantity: 1,
      stock: 5,
      public_id: "pub_r70is_#{SecureRandom.hex(4)}"
    )
    out_of_stock = Commerce::Product.create!(
      name: "OOS WL",
      slug: "r70-oos-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: :active,
      price_cents: 100,
      currency: "CNY",
      minimum_quantity: 1,
      stock: 0,
      public_id: "pub_r70oos_#{SecureRandom.hex(4)}"
    )
    Commerce::WishlistItem.create!(user: owner, product: in_stock)
    Commerce::WishlistItem.create!(user: owner, product: out_of_stock)

    get store_public_wishlist_path(owner.wishlist_share_token, in_stock: "1")
    assert_response :success
    assert_includes response.body, in_stock.name
    assert_not_includes response.body, out_of_stock.name
    assert_includes response.body, "filters"
  end

  test "wishlist filter preset exposes public share url" do
    user = create_user
    Commerce::EnsureWishlistShareToken.call(user: user)
    sign_in_as(user)

    post store_wishlist_filter_presets_path, params: {
      wishlist_filter_preset: {
        name: "有货",
        filters: { in_stock: true }
      }
    }, as: :json

    assert_response :created
    body = JSON.parse(response.body)
    assert body["public_share_url"].present?
    assert_includes body["public_share_url"], "in_stock=1"
  end
end

class Round70PmShowPaginationTest < ActiveSupport::TestCase
  test "conversation show uses page param for pagination" do
    content = File.read(Rails.root.join("app/javascript/pages/Community/Messages/Show.vue"))
    assert_includes content, 'page-param="page"'
    assert_includes content, "canAddParticipant"
  end
end
