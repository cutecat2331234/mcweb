# frozen_string_literal: true

require "test_helper"

class Round109DraftApprovalBypassTest < ActiveSupport::TestCase
  setup do
    SiteSetting.set("forum.require_post_approval_below_tl", "1")
    @user = create_user(forum_trust_level_override: 0)
    category = Community::Category.find_or_create_by!(slug: "r109-draft") { |c| c.name = "D" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r109-draft-sec") { |s| s.name = "Sec"; s.position = 0 }
    @draft = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @user,
      title: "Draft topic",
      status: "draft",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    @post = Community::Post.create!(topic: @draft, user: @user, body: "Draft body", floor_number: 1, status: "published")
  end

  test "publish topic draft requires approval for low trust user" do
    result = Community::PublishTopicDraft.call(user: @user, topic: @draft)
    assert result.success?
    assert_equal "hidden", @draft.reload.status
    assert_equal "pending_approval", @post.reload.status
  end
end

class Round109ScheduledApprovalBypassTest < ActiveSupport::TestCase
  setup do
    SiteSetting.set("forum.require_post_approval_below_tl", "1")
    @user = create_user(forum_trust_level_override: 0)
    category = Community::Category.find_or_create_by!(slug: "r109-sched") { |c| c.name = "S" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r109-sched-sec") { |s| s.name = "Sec"; s.position = 0 }
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @user,
      title: "Scheduled topic",
      status: "draft",
      scheduled_at: 1.minute.ago,
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    @post = Community::Post.create!(topic: @topic, user: @user, body: "Scheduled body", floor_number: 1, status: "published")
  end

  test "publish scheduled topic requires approval for low trust user" do
    result = Community::PublishScheduledTopic.call(topic: @topic)
    assert result.success?
    assert_equal "hidden", @topic.reload.status
    assert_equal "pending_approval", @post.reload.status
  end
end

class Round109SearchSuggestLoginRequiredTest < ActionDispatch::IntegrationTest
  setup do
    category = Community::Category.find_or_create_by!(slug: "r109-suggest") { |c| c.name = "G" }
    @public_section = Community::Section.find_or_create_by!(category: category, slug: "r109-suggest-pub") { |s| s.name = "Public"; s.position = 0 }
    @private_section = Community::Section.find_or_create_by!(category: category, slug: "r109-suggest-priv") { |s| s.name = "Private"; s.position = 1; s.login_required = true }
    @user = create_user(forum_trust_level_override: 0)
    Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @public_section,
      user: @user,
      title: "Public suggest topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @private_section,
      user: @user,
      title: "Private suggest topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
  end

  test "search suggest hides login required topics from guests" do
    get forum_search_suggest_path(q: "suggest topic")
    assert_response :success
    body = response.parsed_body
    titles = body.fetch("topics").map { |row| row["title"] }
    assert_includes titles, "Public suggest topic"
    refute_includes titles, "Private suggest topic"
  end
end

class Round109UserProfileLoginRequiredTest < ActionDispatch::IntegrationTest
  setup do
    category = Community::Category.find_or_create_by!(slug: "r109-profile") { |c| c.name = "P" }
    @private_section = Community::Section.find_or_create_by!(category: category, slug: "r109-profile-priv") { |s| s.name = "Private"; s.position = 0; s.login_required = true }
    @user = create_user(username: "r109profileuser")
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @private_section,
      user: @user,
      title: "Private profile topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    Community::Post.create!(topic: @topic, user: @user, body: "private profile post", floor_number: 1, status: "published")
  end

  test "user profile hides login required topics from guests" do
    get forum_user_path(@user.username)
    assert_response :success
    refute_includes response.body, "Private profile topic"
    refute_includes response.body, "private profile post"
  end
end

class Round109UserCustomFieldsTest < ActiveSupport::TestCase
  setup do
    @user = create_user(forum_trust_level_override: 0)
    @definition = Community::UserFieldDefinition.create!(
      key: "discord",
      label: "Discord",
      field_type: "text",
      visibility: "public",
      show_on_profile: true,
      show_on_registration: true,
      required: true
    )
  end

  test "sync user field values on profile" do
    result = Community::SyncUserFieldValues.call(user: @user, values: { discord: "player#1234" }, context: :profile)
    assert result.success?
    assert_equal "player#1234", @user.forum_user_field_values.find_by(definition: @definition).value
  end

  test "serialize user fields for profile" do
    Community::UserFieldValue.create!(user: @user, definition: @definition, value: "player#1234")
    fields = Community::SerializeUserFields.for(user: @user, viewer: nil)
    assert_equal 1, fields.size
    assert_equal "player#1234", fields.first[:value]
  end

  test "registration requires configured fields" do
    result = Identity::RegisterUser.call(
      email: "r109fields@example.com",
      username: "r109fieldsuser",
      password: "secret12",
      user_fields: {},
      ip_address: "127.0.0.1"
    )
    refute result.success?
    assert result.errors.key?("discord") || result.errors.key?(:discord)
  end
end

class Round109PendingPostNotificationPathTest < ActiveSupport::TestCase
  setup do
    @mod = create_user
    grant_permission(@mod, "forum.topics.lock")
    category = Community::Category.find_or_create_by!(slug: "r109-notify") { |c| c.name = "N" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r109-notify-sec") { |s| s.name = "Sec"; s.position = 0 }
    author = create_user
    topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: author,
      title: "Notify topic",
      status: "hidden",
      last_posted_at: Time.current,
      last_post_user: author,
      replies_count: 0
    )
    @post = Community::Post.create!(topic: topic, user: author, body: "Pending", floor_number: 1, status: "pending_approval")
    NotificationPreference.find_or_create_by!(user: @mod, channel: "in_app", notification_type: "forum.post_pending") do |pref|
      pref.enabled = true
    end
  end

  test "pending post notification includes admin approval path" do
    Community::NotifyPendingPost.call(post: @post)
    notification = Notification.find_by(user: @mod, notification_type: "forum.post_pending")
    assert notification.destination_path.include?("/forum/topics/")
    assert_includes notification.destination_path, "post-#{@post.id}"
  end
end
