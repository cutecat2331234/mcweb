# frozen_string_literal: true

require "test_helper"

class Round111SectionModeratorTest < ActiveSupport::TestCase
  setup do
    category = Community::Category.find_or_create_by!(slug: "r111-mod") { |c| c.name = "M" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r111-mod-sec") do |s|
      s.name = "Mod Section"
      s.position = 0
      s.read_only = true
    end
    @mod = create_user(username: "r111sectionmod")
    @user = create_user
    Community::SectionModerator.create!(section: @section, user: @mod)
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @user,
      title: "Moderated topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    Community::Post.create!(topic: @topic, user: @user, body: "OP", floor_number: 1, status: "published")
  end

  test "section moderator can moderate topic" do
    assert Community::SectionModeration.can_moderate_topic?(user: @mod, topic: @topic)
    refute Community::SectionModeration.can_moderate_topic?(user: @user, topic: @topic)
  end

  test "section moderator can post in read only section" do
    assert @section.writable_by?(@mod, :reply)
    refute @section.writable_by?(@user, :reply)
  end

  test "section moderator can approve pending post" do
    post = Community::Post.create!(
      topic: @topic,
      user: @user,
      floor_number: 2,
      body: "Pending",
      status: "pending_approval"
    )
    result = Community::ApprovePost.call(actor: @mod, post: post)
    assert result.success?
    assert_equal "published", post.reload.status
  end

  test "sync section moderators by username" do
    other = create_user(username: "r111othermod")
    result = Community::SyncSectionModerators.call(section: @section, usernames: [ @mod.username, other.username ])
    assert result.success?
    assert_equal 2, @section.moderators.count
  end
end

class Round111PendingNotificationStaffTest < ActiveSupport::TestCase
  setup do
    category = Community::Category.find_or_create_by!(slug: "r111-notify") { |c| c.name = "N" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r111-notify-sec") { |s| s.name = "Sec"; s.position = 0 }
    @section_mod = create_user(username: "r111notifymod")
    Community::SectionModerator.create!(section: @section, user: @section_mod)
    author = create_user
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: author,
      title: "Notify",
      status: "hidden",
      last_posted_at: Time.current,
      last_post_user: author,
      replies_count: 0
    )
    @post = Community::Post.create!(topic: @topic, user: author, body: "Pending", floor_number: 1, status: "pending_approval")
    NotificationPreference.find_or_create_by!(user: @section_mod, channel: "in_app", notification_type: "forum.post_pending") do |pref|
      pref.enabled = true
    end
  end

  test "pending post notifies section moderator" do
    Community::NotifyPendingPost.call(post: @post)
    notification = Notification.find_by(user: @section_mod, notification_type: "forum.post_pending")
    assert notification
    assert_includes notification.destination_path, @topic.public_id
    assert_includes notification.destination_path, "post-#{@post.id}"
  end
end

class Round111CreateTopicAttachmentsTest < ActiveSupport::TestCase
  setup do
    @user = create_user(forum_trust_level_override: 1)
    category = Community::Category.find_or_create_by!(slug: "r111-topic-attach") { |c| c.name = "A" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r111-topic-attach-sec") { |s| s.name = "Sec"; s.position = 0 }
  end

  test "create topic links attachments to opening post" do
    file = Tempfile.new([ "notes", ".txt" ])
    file.write("topic attachment")
    file.rewind
    upload_file = ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: "notes.txt", type: "text/plain")
    upload = Community::CreatePostAttachment.call(user: @user, file: upload_file)
    assert upload.success?

    result = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "Topic with attachment",
      body: "Body",
      attachment_ids: [ upload.value.id ]
    )
    assert result.success?
    opening_post = result.value.posts.first
    assert_equal 1, opening_post.attachments.count
  end
end
