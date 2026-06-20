# frozen_string_literal: true

require "test_helper"

class Round110MarkdownUploadPermissionTest < ActiveSupport::TestCase
  test "guest cannot upload images" do
    refute Community::TrustLevel.can_upload_images?(nil)
    refute Community::TrustLevel.can_upload_attachments?(nil)
  end

  test "tl0 user cannot upload attachments" do
    user = create_user(forum_trust_level_override: 0)
    refute Community::TrustLevel.can_upload_attachments?(user)
  end

  test "tl1 user can upload attachments" do
    user = create_user(forum_trust_level_override: 1)
    assert Community::TrustLevel.can_upload_attachments?(user)
  end
end

class Round110PostAttachmentTest < ActiveSupport::TestCase
  setup do
    @user = create_user(forum_trust_level_override: 1)
    category = Community::Category.find_or_create_by!(slug: "r110-attach") { |c| c.name = "A" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r110-attach-sec") { |s| s.name = "Sec"; s.position = 0 }
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @user,
      title: "Attachment topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    Community::Post.create!(topic: @topic, user: @user, body: "OP", floor_number: 1, status: "published")
  end

  test "create post links attachments" do
    file = uploaded_file("notes.txt", "text/plain", "hello attachment")
    upload = Community::CreatePostAttachment.call(user: @user, file: file)
    assert upload.success?

    result = Community::CreatePost.call(
      user: @user,
      topic: @topic,
      body: "Reply with attachment",
      attachment_ids: [ upload.value.id ],
      skip_interval_check: true
    )
    assert result.success?
    assert_equal 1, result.value.attachments.count
  end

  test "guest cannot download attachment from login required section" do
    @section.update!(login_required: true)
    post = Community::Post.create!(topic: @topic, user: @user, body: "Secret", floor_number: 2, status: "published")
    attachment = Community::PostAttachment.create!(post: post, user: @user, filename: "secret.txt", byte_size: 4)
    attachment.file.attach(io: StringIO.new("test"), filename: "secret.txt", content_type: "text/plain")

    refute Community::PostAttachmentAccess.downloadable?(attachment, user: nil)
    assert Community::PostAttachmentAccess.downloadable?(attachment, user: @user)
  end

  test "rejects disallowed attachment types" do
    file = uploaded_file("virus.exe", "application/octet-stream", "bad")
    result = Community::CreatePostAttachment.call(user: @user, file: file)
    refute result.success?
  end

  def uploaded_file(name, content_type, content)
    tempfile = Tempfile.new([ File.basename(name, ".*"), File.extname(name) ])
    tempfile.write(content)
    tempfile.rewind
    ActionDispatch::Http::UploadedFile.new(tempfile: tempfile, filename: name, type: content_type)
  end
end

class Round110BookmarksLoginRequiredTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r110-bookmark") { |c| c.name = "B" }
    @private_section = Community::Section.find_or_create_by!(category: category, slug: "r110-bookmark-priv") { |s| s.name = "Private"; s.position = 0; s.login_required = true }
    author = create_user
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @private_section,
      user: author,
      title: "Private bookmark topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: author,
      replies_count: 0
    )
    Community::Bookmark.create!(user: @user, topic: @topic)
  end

  test "bookmarks accessible_by scope hides login required for guests" do
    titles = Community::Topic.published_listed.accessible_by(nil).pluck(:title)
    refute_includes titles, "Private bookmark topic"
  end
end
