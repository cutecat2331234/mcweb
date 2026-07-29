# frozen_string_literal: true

require "test_helper"

class DeveloperModeAuthorizationBoundariesTest <
    ActionDispatch::IntegrationTest
  test "does not grant admin access or system settings permission" do
    member = create_user
    sign_in_as(member)

    with_developer_mode do
      get admin_root_path
      assert_redirected_to root_path

      get admin_system_settings_path
      assert_redirected_to root_path
    end
  end

  test "does not reveal another user's private conversation" do
    sender = create_user
    recipient = create_user
    outsider = create_user
    secret = "private-#{SecureRandom.hex(24)}"
    conversation = Community::Conversation.create!(
      creator: sender,
      is_group: false,
      last_message_at: Time.current
    )
    conversation.participants.create!(user: sender)
    conversation.participants.create!(user: recipient)
    conversation.messages.create!(user: sender, body: secret)
    sign_in_as(outsider)

    with_developer_mode do
      get forum_conversation_path(conversation)

      assert_response :not_found
      refute_includes response.body, secret
    end
  end

  test "does not reveal an attachment in a restricted section" do
    author = create_user
    outsider = create_user
    permission_key = "forum.developer_mode.private_attachment"
    grant_permission(author, permission_key)
    category = Community::Category.create!(
      name: "Developer boundaries",
      slug: "developer-boundaries-#{SecureRandom.hex(5)}"
    )
    section = Community::Section.create!(
      category: category,
      name: "Restricted section",
      slug: "developer-restricted-#{SecureRandom.hex(5)}",
      position: 0,
      permissions: { "view" => [ permission_key ] }
    )
    topic = Community::Topic.create!(
      section: section,
      user: author,
      title: "Private attachment",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: author
    )
    post = Community::Post.create!(
      topic: topic,
      user: author,
      body: "Private attachment body",
      floor_number: 1,
      status: "published"
    )
    attachment = Community::PostAttachment.create!(
      post: post,
      user: author,
      filename: "private.txt",
      content_type: "text/plain",
      byte_size: 7
    )
    attachment.file.attach(
      io: StringIO.new("private"),
      filename: "private.txt",
      content_type: "text/plain",
      identify: false
    )
    blob = attachment.file.blob
    upload = Community::Upload.create!(
      user: author,
      blob: blob,
      post_attachment: attachment,
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
    sign_in_as(outsider)

    with_developer_mode do
      get forum_attachment_path(attachment)

      assert_response :forbidden
      assert_empty response.body
      assert_equal 0, attachment.reload.download_count
    end
  ensure
    if upload&.persisted?
      Community::CleanupUpload.call(upload: upload, force: true)
    elsif attachment&.persisted? && attachment.file.attached?
      attachment.file.purge
    end
  end

  private

  def with_developer_mode
    settings = Mcweb::DeveloperMode.parse(
      config: {
        developer_mode: {
          enabled: true,
          preset: "unrestricted"
        }
      },
      environment: {}
    )
    previous_settings =
      Mcweb::DeveloperMode.instance_variable_get(:@settings)
    Mcweb::DeveloperMode.instance_variable_set(:@settings, settings)
    yield
  ensure
    Mcweb::DeveloperMode.instance_variable_set(
      :@settings,
      previous_settings
    )
  end
end
