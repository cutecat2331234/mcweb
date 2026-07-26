# frozen_string_literal: true

require "test_helper"

class CommunityAttachmentDownloadSecurityTest < ActionDispatch::IntegrationTest
  setup do
    suffix = SecureRandom.hex(5)
    category = Community::Category.create!(
      name: "Attachment security #{suffix}",
      slug: "attachment-security-#{suffix}"
    )
    section = Community::Section.create!(
      category: category,
      name: "Protected attachments #{suffix}",
      slug: "protected-attachments-#{suffix}",
      position: 0,
      permissions: { "view" => [ "forum.attachments.security_test" ] }
    )
    @author = create_user
    grant_permission(@author, "forum.attachments.security_test")
    topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @author,
      title: "Protected attachment #{suffix}",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @author,
      replies_count: 0
    )
    post = Community::Post.create!(
      topic: topic,
      user: @author,
      body: "Attachment body",
      floor_number: 1,
      status: "published"
    )
    @payload = "classified attachment"
    @attachment = Community::PostAttachment.create!(
      post: post,
      user: @author,
      filename: "notes.txt",
      content_type: "text/html",
      byte_size: @payload.bytesize
    )
    @attachment.file.attach(
      io: StringIO.new(@payload),
      filename: "notes.txt",
      content_type: "text/html",
      identify: false
    )
    blob = @attachment.file.blob
    @upload = Community::Upload.create!(
      user: @author,
      blob: blob,
      post_attachment: @attachment,
      post: post,
      public_id: Community::Upload.generate_public_id,
      kind: "post_attachment",
      status: "linked",
      scan_status: "clean",
      scanner: "test_scanner",
      scan_result_code: "clean",
      scanned_at: Time.current,
      byte_size: blob.byte_size
    )
  end

  teardown do
    if @upload&.persisted?
      Community::CleanupUpload.call(upload: @upload, force: true)
    elsif @attachment.persisted? && @attachment.file.attached?
      @attachment.file.purge
    end
  end

  test "authorized download is proxied with canonical type and non-cacheable security headers" do
    sign_in_as(@author)

    get forum_attachment_path(@attachment)

    assert_response :success
    assert_equal @payload, response.body
    assert_nil response.headers["Location"]
    assert_equal "text/plain", response.media_type
    assert_includes response.headers["Content-Disposition"], "attachment"
    assert_includes response.headers["Content-Disposition"], "notes.txt"
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_includes response.headers["Cache-Control"], "private"
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_equal "no-cache", response.headers["Pragma"]
    assert_equal "sandbox", response.headers["Content-Security-Policy"]
    assert_equal "same-origin", response.headers["Cross-Origin-Resource-Policy"]
    assert_equal @payload.bytesize.to_s, response.headers["Content-Length"]
    assert_equal 1, @attachment.reload.download_count
  end

  test "authorized user cannot download an attachment before a clean scan" do
    @upload.update!(
      scan_status: "pending",
      scanned_at: nil,
      scanner: nil,
      scan_result_code: nil
    )
    sign_in_as(@author)

    get forum_attachment_path(@attachment)

    assert_response :locked
    assert_empty response.body
    assert_equal 0, @attachment.reload.download_count
  end

  test "uploader can poll the private scan status endpoint" do
    sign_in_as(@author)

    get scan_status_forum_attachment_path(@attachment)

    assert_response :success
    payload = response.parsed_body
    assert_equal "clean", payload.fetch("scan_status")
    assert_equal @attachment.id, payload.dig("attachment", "id")

    delete identity_session_path
    sign_in_as(create_user)
    get scan_status_forum_attachment_path(@attachment)
    assert_response :forbidden
  end

  test "guest cannot turn the attachment endpoint into a reusable blob link" do
    get forum_attachment_path(@attachment)

    assert_response :forbidden
    assert_nil response.headers["Location"]
    assert_empty response.body
    assert_equal 0, @attachment.reload.download_count
  end

  test "signed in user without section access cannot download by attachment id" do
    sign_in_as(create_user)

    get forum_attachment_path(@attachment)

    assert_response :forbidden
    assert_nil response.headers["Location"]
    assert_empty response.body
    assert_equal 0, @attachment.reload.download_count
  end
end
