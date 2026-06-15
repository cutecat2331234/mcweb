# frozen_string_literal: true

require "test_helper"

class Round66WishlistImportCompareTest < ActionDispatch::IntegrationTest
  test "wishlist page exposes import compare props" do
    user = create_user
    product = Commerce::Product.create!(
      name: "Wishlist Import",
      slug: "r66-wi-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: :active,
      price_cents: 100,
      currency: "CNY",
      minimum_quantity: 1,
      stock: 5,
      public_id: "pub_r66wi_#{SecureRandom.hex(4)}"
    )
    Commerce::WishlistItem.create!(user: user, product: product)

    sign_in_as(user)
    get store_wishlist_path
    assert_response :success
    assert_includes response.body, "wishlistImportCompareUrl"
    assert_includes response.body, "wishlistImportableCount"
  end
end

class Round66AddWishlistCompareLimitTest < ActiveSupport::TestCase
  test "marks products skipped when compare limit reached during import" do
    user = create_user
    session = {}
    max = Commerce::ToggleCompare.compare_max_items

    (max + 1).times do |i|
      product = Commerce::Product.create!(
        name: "Limit #{i}",
        slug: "r66-lim-#{i}-#{SecureRandom.hex(3)}",
        product_type: "virtual",
        status: :active,
        price_cents: 100,
        currency: "CNY",
        minimum_quantity: 1,
        stock: 5,
        public_id: "pub_r66l_#{i}_#{SecureRandom.hex(3)}"
      )
      Commerce::WishlistItem.create!(user: user, product: product)
    end

    result = Commerce::AddWishlistToCompare.call(user: user, session: session)
    assert result.success?
    assert_equal max, result.value[:added]
    assert result.value[:skipped].any? { |s| s.include?("对比已满") }
  end
end

class Round66PublishDraftWarningTest < ActiveSupport::TestCase
  test "publish draft rejects warned user posting links" do
    user = create_user
    SiteSetting.set("forum.warning_block_links_threshold", "1")
    Community::UserWarning.create!(user: user, issuer: user, reason: "test", points: 5)

    category = Community::Category.find_or_create_by!(slug: "r66-cat-#{SecureRandom.hex(4)}") { |c| c.name = "R66" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r66-sec-#{SecureRandom.hex(4)}") { |s| s.name = "S"; s.position = 0 }

    topic = Community::Topic.create!(
      user: user,
      section: section,
      title: "Draft",
      status: :draft,
      public_id: "topic_r66_#{SecureRandom.hex(8)}"
    )
    Community::Post.create!(
      topic: topic,
      user: user,
      body: "Check https://example.com",
      floor_number: 1,
      status: :published
    )

    result = Community::PublishTopicDraft.call(user: user, topic: topic)
    assert result.failure?
    assert_match(/链接/, result.error)
  end
end

class Round66EditPostLinkTest < ActiveSupport::TestCase
  test "edit post rejects warned user adding links" do
    user = create_user
    SiteSetting.set("forum.warning_block_links_threshold", "1")
    Community::UserWarning.create!(user: user, issuer: user, reason: "test", points: 5)

    category = Community::Category.find_or_create_by!(slug: "r66e-cat-#{SecureRandom.hex(4)}") { |c| c.name = "R66E" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r66e-sec-#{SecureRandom.hex(4)}") { |s| s.name = "S"; s.position = 0 }
    topic = Community::Topic.create!(
      user: user,
      section: section,
      title: "Topic",
      status: :published,
      public_id: "topic_r66e_#{SecureRandom.hex(8)}"
    )
    post = Community::Post.create!(
      topic: topic,
      user: user,
      body: "Original body text here",
      floor_number: 1,
      status: :published
    )

    result = Community::EditPost.call(user: user, post: post, body: "Now with https://example.com link")
    assert result.failure?
    assert_match(/链接/, result.error)
  end
end

class Round66CreateConversationLinkTest < ActiveSupport::TestCase
  test "create conversation rejects warned user sending links" do
    sender = create_user
    recipient = create_user(username: "r66recv#{SecureRandom.hex(4)}")
    enable_forum_pm!(sender)
    SiteSetting.set("forum.warning_block_links_threshold", "1")
    Community::UserWarning.create!(user: sender, issuer: sender, reason: "test", points: 5)

    result = Community::CreateConversation.call(
      sender: sender,
      recipient_username: recipient.username,
      body: "See https://example.com"
    )
    assert result.failure?
    assert_match(/链接/, result.error)
  end
end
