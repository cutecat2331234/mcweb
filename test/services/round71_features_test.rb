# frozen_string_literal: true

require "test_helper"

class Round71SearchSuggestUiTest < ActionDispatch::IntegrationTest
  test "search page has suggest dropdown" do
    content = File.read(Rails.root.join("app/javascript/pages/Community/Search/Index.vue"))
    assert_includes content, "suggestUrl"
    assert_includes content, "fetchSuggestions"
    assert_includes content, "suggestTopics"
  end

  test "search index exposes suggest url" do
    get forum_search_path
    assert_response :success
    assert_includes response.body, "suggestUrl"
  end
end

class Round71SearchSuggestApiTest < ActionDispatch::IntegrationTest
  test "suggest returns topics tags users" do
    user = create_user
    suffix = SecureRandom.hex(4)
    category = Community::Category.find_or_create_by!(slug: "r71-#{suffix}") { |c| c.name = "R71" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r71-sec-#{suffix}") { |s| s.name = "S"; s.position = 0 }
    Community::CreateTopic.call(user: user, section: section, title: "SuggestTopic#{suffix}", body: "OP", ip_address: "127.0.0.1")

    get forum_search_suggest_path, params: { q: "SuggestTopic" }, as: :json
    assert_response :success
    body = JSON.parse(response.body)
    assert body["topics"].any? { |t| t["title"].include?("SuggestTopic") }
  end
end

class Round71FeaturedWishlistCompareTest < ActionDispatch::IntegrationTest
  test "store index includes compare and wishlist on featured products" do
    user = create_user
    Commerce::Product.create!(
      name: "Featured R71",
      slug: "r71-feat-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: :active,
      featured: true,
      price_cents: 100,
      currency: "CNY",
      minimum_quantity: 1,
      stock: 5,
      public_id: "pub_r71ft_#{SecureRandom.hex(4)}"
    )

    sign_in_as(user)
    get store_products_path
    assert_response :success
    assert_includes response.body, "featured_products"
    assert_includes response.body, "wishlist_url"
    assert_includes response.body, "compare_url"
  end
end

class Round71GroupCreatorOnlyAddTest < ActionDispatch::IntegrationTest
  setup do
    @previous = SiteSetting.get("forum.group_pm_creator_only_add")
    SiteSetting.set("forum.group_pm_creator_only_add", "true")
  end

  teardown do
    SiteSetting.set("forum.group_pm_creator_only_add", @previous || "false")
  end

  test "non-creator cannot add group members when setting enabled" do
    creator = create_user
    member = create_user(username: "r71mem#{SecureRandom.hex(4)}")
    invitee = create_user(username: "r71inv#{SecureRandom.hex(4)}")
    enable_forum_pm!(creator)
    enable_forum_pm!(member)
    enable_forum_pm!(invitee)

    result = Community::CreateGroupConversation.call(
      sender: creator,
      title: "R71 Creator Group",
      recipient_usernames: [ member.username ],
      body: "Hi"
    )
    conv = result.value[:conversation]

    add = Community::AddConversationParticipant.call(
      actor: member,
      conversation: conv,
      username: invitee.username
    )
    assert add.failure?
    assert_includes add.error.to_s.downcase, "creator"
  end

  test "creator can add group members when setting enabled" do
    creator = create_user
    member = create_user(username: "r71mem2#{SecureRandom.hex(4)}")
    invitee = create_user(username: "r71inv2#{SecureRandom.hex(4)}")
    enable_forum_pm!(creator)
    enable_forum_pm!(member)
    enable_forum_pm!(invitee)

    result = Community::CreateGroupConversation.call(
      sender: creator,
      title: "R71 Creator Group2",
      recipient_usernames: [ member.username ],
      body: "Hi"
    )
    conv = result.value[:conversation]

    add = Community::AddConversationParticipant.call(
      actor: creator,
      conversation: conv,
      username: invitee.username
    )
    assert add.success?
  end

  test "conversation show exposes restricted reason for non-creator" do
    creator = create_user
    member = create_user(username: "r71mem3#{SecureRandom.hex(4)}")
    enable_forum_pm!(creator)
    enable_forum_pm!(member)

    result = Community::CreateGroupConversation.call(
      sender: creator,
      title: "R71 Show Group",
      recipient_usernames: [ member.username ],
      body: "Hi"
    )
    conv = result.value[:conversation]

    sign_in_as(member)
    get forum_conversation_path(conv)
    assert_response :success
    assert_includes response.body, "addParticipantRestrictedReason"
    assert_includes response.body, "仅群主可添加新成员"
  end
end

class Round71SearchPostPaginationTest < ActionDispatch::IntegrationTest
  test "search post pagination uses post_page param" do
    user = create_user
    suffix = SecureRandom.hex(4)
    category = Community::Category.find_or_create_by!(slug: "r71pg-#{suffix}") { |c| c.name = "R71PG" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r71pg-sec-#{suffix}") { |s| s.name = "S"; s.position = 0 }
    topic = Community::CreateTopic.call(
      user: user,
      section: section,
      title: "PaginationTopic#{suffix}",
      body: "OP uniqueword#{suffix}",
      ip_address: "127.0.0.1"
    ).value

    16.times do |i|
      Community::Post.create!(
        topic: topic,
        user: user,
        body: "reply uniqueword#{suffix} number #{i}",
        floor_number: i + 2,
        status: :published
      )
    end

    matching = Community::Post.published.joins(:topic)
      .where("forum_posts.body ILIKE ?", "%uniqueword#{suffix}%")
      .count
    assert_operator matching, :>=, 16, "expected at least 16 matching posts"

    get forum_search_path, params: { q: "uniqueword#{suffix}", post_page: 2 }
    assert_response :success
    assert_includes response.body, "postsPagination"
    assert_match(/"postsPagination":\{[^}]*"page":2/, response.body)
  end
end
