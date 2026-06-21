# frozen_string_literal: true

require "test_helper"

module Round78TestHelpers
  def self.create_section_pair
    category = Community::Category.find_or_create_by!(slug: "r78-cat-#{SecureRandom.hex(4)}") { |c| c.name = "R78 Cat" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r78-sec-#{SecureRandom.hex(4)}") do |s|
      s.name = "R78 Sec"
      s.position = 0
    end
    [ category, section ]
  end
end

class Round78SavedSearchMatcherFiltersTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    _category, @section = Round78TestHelpers.create_section_pair
    @locked = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.hex(8)}",
      section: @section,
      user: @user,
      title: "LockedMatch",
      status: :published,
      locked: true,
      last_posted_at: Time.current,
      last_post_user: @user
    )
    @unlocked = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.hex(8)}",
      section: @section,
      user: @user,
      title: "OpenMatch",
      status: :published,
      locked: false,
      last_posted_at: Time.current,
      last_post_user: @user
    )
    @search = @user.forum_saved_searches.create!(
      name: "Locked only",
      query: "LockedMatch",
      filters: { locked: "locked", section: @section.slug }
    )
  end

  test "matcher applies locked filter from saved search" do
    topics = Community::SavedSearchMatcher.new(@search).matching_topics
    ids = topics.pluck(:id)
    assert_includes ids, @locked.id
    assert_not_includes ids, @unlocked.id
  end
end

class Round78SavedSearchOpmlTest < ActionDispatch::IntegrationTest
  test "opml export lists saved searches" do
    user = create_user
    user.forum_saved_searches.create!(name: "Feed A", query: "a", filters: {})
    user.forum_saved_searches.create!(name: "Feed B", query: "b", filters: {})
    token = Community::SavedSearchOpmlToken.generate(user)

    get forum_saved_searches_opml_path(token: token)
    assert_response :success
    assert_includes response.body, "<opml"
    assert_includes response.body, "Feed A"
    assert_includes response.body, "Feed B"
    assert_includes response.body, "type=\"rss\""
  end

  test "search page exposes opml url" do
    user = create_user
    sign_in_as(user)
    get forum_search_path
    assert_response :success
    assert_includes response.body, "savedSearchesOpmlUrl"
  end
end

class Round78SavedSearchWebhookTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @previous_hour = SiteSetting.get("forum.saved_search_digest_hour")
    SiteSetting.set("forum.saved_search_digest_hour", Time.current.hour.to_s)
    @user = create_user
    _category, @section = Round78TestHelpers.create_section_pair
    @search = @user.forum_saved_searches.create!(
      name: "Hook",
      query: "WebhookWord",
      notify_daily: true,
      webhook_url: "https://example.com/hooks/saved-search",
      filters: { section: @section.slug }
    )
    Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "WebhookWord fresh",
      body: "OP",
      ip_address: "127.0.0.1"
    )
  end

  teardown do
    SiteSetting.set("forum.saved_search_digest_hour", @previous_hour || "9")
  end

  test "digest dispatch enqueues saved search webhook" do
    assert_enqueued_with(job: Community::DispatchSavedSearchWebhookJob) do
      Community::SendSavedSearchDigests.call
    end
  end
end

class Round78ForumDigestUnsubscribeTest < ActionDispatch::IntegrationTest
  test "digest unsubscribe disables forum digest" do
    user = create_user
    user.update!(forum_digest_frequency: "daily")
    token = Community::ForumDigestUnsubscribeToken.generate(user)

    get forum_unsubscribe_forum_digest_path(token: token)
    assert_redirected_to root_path
    assert_equal "none", user.reload.forum_digest_frequency
  end

  test "digest email template includes unsubscribe url" do
    content = File.read(Rails.root.join("app/views/community/forum_mailer/digest.html.erb"))
    assert_includes content, "@unsubscribe_url"
  end
end

class Round78ForumDigestHourTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "forum digest job skips wrong hour" do
    previous = SiteSetting.get("forum.digest_hour")
    SiteSetting.set("forum.digest_hour", (Time.current.hour + 1) % 24)
    user = create_user(email: "digest-r78@example.com")
    user.update!(forum_digest_frequency: "daily")

    assert_no_enqueued_jobs only: MailDeliveryJob do
      Community::ForumDigestJob.perform_now
    end
  ensure
    SiteSetting.set("forum.digest_hour", previous || "8")
  end
end

class Round78AdminSettingsTest < ActiveSupport::TestCase
  test "forum settings include digest hour and op close" do
    content = File.read(Rails.root.join("app/controllers/admin/forum/settings_controller.rb"))
    assert_includes content, "forum.digest_hour"
    assert_includes content, "forum.allow_op_close"
    assert_includes content, "forum.min_trust_level_reaction"
  end

  test "store settings include order webhook url" do
    content = File.read(Rails.root.join("app/controllers/admin/store/settings_controller.rb"))
    assert_includes content, "store.order_webhook_url"
  end
end

class Round78OrderMailDeliveryEstimateTest < ActiveSupport::TestCase
  test "order details partial shows delivery estimate" do
    content = File.read(Rails.root.join("app/views/commerce/order_mailer/_order_details.html.erb"))
    assert_includes content, "mcweb.mail.commerce.delivery_estimate_label"
  end
end

class Round78BuildSavedSearchTopicScopeTest < ActiveSupport::TestCase
  test "service is used by matcher" do
    content = File.read(Rails.root.join("app/services/community/saved_search_matcher.rb"))
    assert_includes content, "BuildSavedSearchTopicScope"
  end
end
