# frozen_string_literal: true

require "test_helper"

class Round117SectionModWhisperTest < ActiveSupport::TestCase
  setup do
    category = Community::Category.find_or_create_by!(slug: "r117-whisper") { |c| c.name = "R" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r117-whisper-sec") { |s| s.name = "S"; s.position = 0 }
    @mod = create_user(username: "r117whispermod")
    Community::SectionModerator.create!(section: @section, user: @mod)
    @user = create_user
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @user,
      title: "Whisper topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    Community::Post.create!(topic: @topic, user: @user, body: "OP", floor_number: 1, status: "published")
  end

  test "section moderator can post staff whisper" do
    result = Community::CreatePost.call(
      user: @mod,
      topic: @topic,
      body: "Staff only note",
      whisper: true,
      skip_interval_check: true
    )
    assert result.success?
    assert result.value.whisper?
  end

  test "regular user cannot post staff whisper" do
    other = create_user
    result = Community::CreatePost.call(
      user: other,
      topic: @topic,
      body: "Not staff",
      whisper: true,
      skip_interval_check: true
    )
    assert result.failure?
  end
end

class Round117PendingAttachmentAccessTest < ActiveSupport::TestCase
  setup do
    category = Community::Category.find_or_create_by!(slug: "r117-att") { |c| c.name = "R" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r117-att-sec") { |s| s.name = "S"; s.position = 0 }
    @mod = create_user(username: "r117attmod")
    Community::SectionModerator.create!(section: @section, user: @mod)
    @author = create_user
    @other = create_user
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @author,
      title: "Pending attachment",
      status: "hidden",
      last_posted_at: Time.current,
      last_post_user: @author,
      replies_count: 0
    )
    @post = Community::Post.create!(topic: @topic, user: @author, body: "Pending", floor_number: 1, status: "pending_approval")
    @attachment = Community::PostAttachment.create!(
      user: @author,
      forum_post_id: @post.id,
      filename: "secret.txt",
      content_type: "text/plain",
      byte_size: 6
    )
    @attachment.file.attach(io: StringIO.new("secret"), filename: "secret.txt", content_type: "text/plain")
  end

  test "other user cannot download pending post attachment" do
    refute Community::PostAttachmentAccess.downloadable?(@attachment, user: @other)
  end

  test "section moderator can download pending post attachment" do
    assert Community::PostAttachmentAccess.downloadable?(@attachment, user: @mod)
  end

  test "author can download own pending post attachment" do
    assert Community::PostAttachmentAccess.downloadable?(@attachment, user: @author)
  end
end

class Round117NotifyPendingPostTest < ActiveSupport::TestCase
  setup do
    category = Community::Category.find_or_create_by!(slug: "r117-notify") { |c| c.name = "R" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r117-notify-sec") { |s| s.name = "S"; s.position = 0 }
    @mod = create_user(username: "r117notifymod")
    Community::SectionModerator.create!(section: @section, user: @mod)
    @author = create_user(username: "r117author")
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @author,
      title: "Notify pending",
      status: "hidden",
      last_posted_at: Time.current,
      last_post_user: @author,
      replies_count: 0
    )
    @post = Community::Post.create!(topic: @topic, user: @author, body: "Pending", floor_number: 1, status: "pending_approval")
  end

  test "notify pending post uses i18n and topic path" do
    I18n.with_locale(:en) do
      Community::NotifyPendingPost.call(post: @post)
      notification = Notification.find_by!(user: @mod, notification_type: "forum.post_pending")
      assert_equal I18n.t("mcweb.labels.notification_types.forum.post_pending"), notification.title
      assert_includes notification.body, @author.username
      assert_includes notification.metadata["path"], @topic.public_id
    end
  end
end

class Round117SaveDraftAttachmentsTest < ActiveSupport::TestCase
  setup do
    category = Community::Category.find_or_create_by!(slug: "r117-draft") { |c| c.name = "R" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r117-draft-sec") { |s| s.name = "S"; s.position = 0 }
    @user = create_user
    @attachment = Community::PostAttachment.create!(
      user: @user,
      filename: "draft.txt",
      content_type: "text/plain",
      byte_size: 5
    )
    @attachment.file.attach(io: StringIO.new("draft"), filename: "draft.txt", content_type: "text/plain")
  end

  test "save topic draft links attachments to opening post" do
    result = Community::SaveTopicDraft.call(
      user: @user,
      section: @section,
      title: "Draft with file",
      body: "Body",
      attachment_ids: [ @attachment.id ]
    )
    assert result.success?
    opening_post = result.value.posts.first
    assert_equal opening_post.id, @attachment.reload.forum_post_id
  end
end
