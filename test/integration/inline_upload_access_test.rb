# frozen_string_literal: true

require "test_helper"

class InlineUploadAccessTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user(forum_trust_level_override: 1)
    @other = create_user(forum_trust_level_override: 1)
    @post = create_post(@owner)
    @upload = store_inline_upload(@owner)
  end

  teardown do
    Community::Upload.where(id: @upload&.id).find_each do |upload|
      Community::CleanupUpload.call(upload: upload, force: true)
    end
  end

  test "unbound inline upload is readable only by its owner" do
    get forum_upload_path(@upload.public_id)
    assert_response :forbidden

    sign_in_as(@other)
    get forum_upload_path(@upload.public_id)
    assert_response :forbidden

    delete identity_session_path
    sign_in_as(@owner)
    get forum_upload_path(@upload.public_id)
    assert_response :success
    assert_equal "image/png", response.media_type
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_includes response.headers["Cache-Control"], "no-store"
  end

  test "bound inline upload follows post visibility and never exposes a storage URL" do
    body = "![image](#{forum_upload_path(@upload.public_id)})"
    @post.update!(body: body)

    result = Community::BindInlineUploads.call(
      user: @owner,
      post: @post,
      body: body
    )

    assert_predicate result, :success?
    assert_equal "linked", @upload.reload.status

    get forum_upload_path(@upload.public_id)
    assert_response :success
    assert_not_includes @post.reload.body, "/rails/active_storage/"
  end

  test "one foreign upload marker rejects the whole inline binding transaction" do
    foreign_upload = store_inline_upload(@other)
    body = [
      "![one](#{forum_upload_path(@upload.public_id)})",
      "![two](#{forum_upload_path(foreign_upload.public_id)})"
    ].join("\n")
    @post.update!(body: body)

    result = Community::BindInlineUploads.call(
      user: @owner,
      post: @post,
      body: body
    )

    assert_predicate result, :failure?
    assert_equal "stored", @upload.reload.status
    assert_equal "stored", foreign_upload.reload.status
    assert_nil @upload.forum_post_id
  ensure
    Community::CleanupUpload.call(upload: foreign_upload, force: true) if foreign_upload&.persisted?
  end

  test "legacy blob URL is rewritten to the protected proxy when bound" do
    legacy_url = "/rails/active_storage/blobs/redirect/signed/file.png?upload=#{@upload.public_id}"
    body = "![legacy](#{legacy_url})"
    @post.update!(body: body)

    result = Community::BindInlineUploads.call(
      user: @owner,
      post: @post,
      body: body
    )

    assert_predicate result, :success?
    assert_equal "![legacy](#{forum_upload_path(@upload.public_id)})", @post.reload.body
  end

  private

  def store_inline_upload(user)
    result = Community::StoreUpload.call(
      user: user,
      kind: :inline_image,
      payload: "\x89PNG\r\n\x1A\nsafe-test-payload".b,
      filename: "safe.png",
      content_type: "image/png"
    )
    assert_predicate result, :success?
    result.value.fetch(:upload)
  end

  def create_post(user)
    suffix = SecureRandom.hex(5)
    category = Community::Category.create!(
      name: "Inline access #{suffix}",
      slug: "inline-access-#{suffix}"
    )
    section = Community::Section.create!(
      category: category,
      name: "Inline access",
      slug: "inline-access-section-#{suffix}",
      position: 0
    )
    topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: user,
      title: "Inline access",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: user,
      replies_count: 0
    )
    Community::Post.create!(
      topic: topic,
      user: user,
      floor_number: 1,
      body: "Opening post",
      status: "published"
    )
  end
end
