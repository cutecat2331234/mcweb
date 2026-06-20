# frozen_string_literal: true

require "test_helper"

class Round72SearchKeyboardNavTest < ActionDispatch::IntegrationTest
  test "search page has keyboard navigation for suggestions" do
    content = File.read(Rails.root.join("app/javascript/pages/Community/Search/Index.vue"))
    assert_includes content, "onSuggestKeydown"
    assert_includes content, "suggestActiveIndex"
    assert_includes content, "flatSuggestions"
    assert_includes content, "saveNotifyDaily"
  end
end

class Round72SavedSearchNotifyDailyTest < ActionDispatch::IntegrationTest
  test "create saved search with notify_daily" do
    user = create_user
    sign_in_as(user)

    post forum_saved_searches_path, params: {
      saved_search: {
        name: "每日提醒",
        query: "release",
        notify_daily: true,
        filters: { solved: "unsolved" }
      }
    }, as: :json

    assert_response :created
    body = JSON.parse(response.body)
    assert body["notify_daily"]
    search = user.forum_saved_searches.find(body["id"])
    assert search.notify_daily?
  end

  test "search page serializes notify_daily on saved searches" do
    user = create_user
    user.forum_saved_searches.create!(name: "Digest", query: "foo", notify_daily: true, filters: {})
    sign_in_as(user)

    get forum_search_path
    assert_response :success
    assert_includes response.body, '"notify_daily":true'
  end
end

class Round72SavedSearchMatcherTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    suffix = SecureRandom.hex(4)
    category = Community::Category.find_or_create_by!(slug: "r72-#{suffix}") { |c| c.name = "R72" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r72-sec-#{suffix}") { |s| s.name = "S"; s.position = 0 }
    @search = Community::SavedSearch.create!(
      user: @user,
      name: "Matcher",
      query: "UniqueR72#{suffix}",
      filters: { section: @section.slug },
      notify_daily: true
    )
    Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "UniqueR72#{suffix} topic",
      body: "OP",
      ip_address: "127.0.0.1"
    )
  end

  test "matching_topics finds new topics since timestamp" do
    matcher = Community::SavedSearchMatcher.new(@search)
    topics = matcher.matching_topics(since: 1.hour.ago)
    assert topics.any? { |t| t.title.include?("UniqueR72") }
  end
end

class Round72SendSavedSearchDigestsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @previous_digest_hour = SiteSetting.get("forum.saved_search_digest_hour")
    SiteSetting.set("forum.saved_search_digest_hour", Time.current.hour.to_s)
    @user = create_user
    suffix = SecureRandom.hex(4)
    category = Community::Category.find_or_create_by!(slug: "r72d-#{suffix}") { |c| c.name = "R72D" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r72d-sec-#{suffix}") { |s| s.name = "S"; s.position = 0 }
    @search = Community::SavedSearch.create!(
      user: @user,
      name: "Digest #{suffix}",
      query: "DigestWord#{suffix}",
      filters: { section: section.slug },
      notify_daily: true
    )
    Community::CreateTopic.call(
      user: @user,
      section: section,
      title: "DigestWord#{suffix} fresh",
      body: "OP",
      ip_address: "127.0.0.1"
    )
  end

  teardown do
    SiteSetting.set("forum.saved_search_digest_hour", @previous_digest_hour || "9")
  end

  test "sends digest when new topics match" do
    assert_enqueued_with(job: MailDeliveryJob) do
      result = Community::SendSavedSearchDigests.call
      assert result.success?
      assert_operator result.value[:sent], :>=, 1
    end
    assert @search.reload.last_notified_at
  end

  test "skips when recently notified" do
    @search.update!(last_notified_at: 1.hour.ago)
    result = Community::SendSavedSearchDigests.call
    assert result.success?
    assert_equal 0, result.value[:sent] || 0
  end
end

class Round72RecentlyViewedCompareWishlistTest < ActionDispatch::IntegrationTest
  test "recently viewed page includes compare and wishlist props" do
    user = create_user
    product = Commerce::Product.create!(
      name: "Recent R72",
      slug: "r72-rv-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: :active,
      price_cents: 100,
      currency: "CNY",
      minimum_quantity: 1,
      stock: 5,
      public_id: "pub_r72rv_#{SecureRandom.hex(4)}"
    )
    Commerce::RecordProductView.call(user: user, product: product)

    sign_in_as(user)
    get recently_viewed_store_products_path
    assert_response :success
    assert_includes response.body, "compare_url"
    assert_includes response.body, "wishlist_url"
    assert_includes response.body, product.name
  end
end

class Round72CategoryCompareWishlistTest < ActionDispatch::IntegrationTest
  test "category page includes compare and wishlist props" do
    user = create_user
    category = Commerce::Category.create!(
      name: "R72 Cat",
      slug: "r72-cat-#{SecureRandom.hex(4)}",
      position: 0
    )
    product = Commerce::Product.create!(
      name: "Category R72",
      slug: "r72-cp-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: :active,
      price_cents: 100,
      currency: "CNY",
      minimum_quantity: 1,
      stock: 5,
      category: category,
      public_id: "pub_r72cp_#{SecureRandom.hex(4)}"
    )

    sign_in_as(user)
    get store_category_path(category.slug)
    assert_response :success
    assert_includes response.body, "compare_url"
    assert_includes response.body, "wishlist_url"
    assert_includes response.body, product.name
  end
end

class Round72RecurringDigestJobTest < ActiveSupport::TestCase
  test "recurring config schedules saved search digest" do
    content = File.read(Rails.root.join("config/sidekiq_cron.yml"))
    assert_includes content, "saved_search_digest"
    assert_includes content, "Community::SavedSearchDigestJob"
  end
end

class Round72GroupPmCreatorSeedTest < ActiveSupport::TestCase
  test "seeds default group_pm_creator_only_add setting" do
    content = File.read(Rails.root.join("db/seeds.rb"))
    assert_includes content, "forum.group_pm_creator_only_add"
  end
end
