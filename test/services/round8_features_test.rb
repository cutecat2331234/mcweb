# frozen_string_literal: true

require "test_helper"

class Community::TrustLevelTest < ActiveSupport::TestCase
  test "new user cannot post links" do
    user = create_user
    assert_not Community::TrustLevel.can_post_links?(user)
    assert Community::TrustLevel.contains_link?("see https://example.com")
  end

  test "user with posts can post links" do
    user = create_user
    category = Community::Category.find_or_create_by!(slug: "trust-cat") { |c| c.name = "Trust" }
    section = Community::Section.find_or_create_by!(category: category, slug: "trust-sec") do |s|
      s.name = "Trust Sec"
      s.position = 0
    end
    Community::CreateTopic.call(
      user: user,
      section: section,
      title: "First",
      body: "Hello world",
      ip_address: "127.0.0.1"
    )
    assert Community::TrustLevel.can_post_links?(user)
    assert_equal 1, Community::TrustLevel.level_for(user)
  end
end

class Community::NotifyPrivateMessageTest < ActiveSupport::TestCase
  setup do
    @sender = create_user
    enable_forum_pm!(@sender)
    @recipient = create_user
  end

  test "notifies recipient of new message" do
    result = Community::CreateConversation.call(
      sender: @sender,
      recipient_username: @recipient.username,
      body: "Hello there"
    )
    assert result.success?
    assert Notification.exists?(user: @recipient, notification_type: "forum.private_message")
  end
end

class Community::TogglePostBookmarkTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "pb-cat") { |c| c.name = "PB" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "pb-sec") do |s|
      s.name = "PB Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "Bookmark post",
      body: "Body",
      ip_address: "127.0.0.1"
    ).value
    @post = @topic.posts.first
  end

  test "toggles post bookmark" do
    add = Community::TogglePostBookmark.call(user: @user, post: @post)
    assert add.success?
    assert add.value[:bookmarked]

    remove = Community::TogglePostBookmark.call(user: @user, post: @post)
    assert remove.success?
    assert_not remove.value[:bookmarked]
  end
end

class Community::CreatePostLinkRestrictionTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "link-cat") { |c| c.name = "Link" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "link-sec") do |s|
      s.name = "Link Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "Links",
      body: "No link here",
      ip_address: "127.0.0.1"
    ).value
  end

  test "new member cannot post links in reply" do
    other = create_user
    result = Community::CreatePost.call(
      user: other,
      topic: @topic,
      body: "Check https://example.com"
    )
    assert result.failure?
  end
end

class Community::TagRssTest < ActionDispatch::IntegrationTest
  test "tag rss feed returns xml" do
    tag = Community::Tag.find_or_create_by!(slug: "rss-tag") { |t| t.name = "rss-tag" }
    get forum_tag_rss_path(tag.slug)
    assert_response :success
    assert_includes response.content_type, "rss"
  end
end

class Community::SitemapTest < ActionDispatch::IntegrationTest
  test "sitemap returns xml" do
    get forum_sitemap_path
    assert_response :success
    assert_includes response.body, "urlset"
  end
end
