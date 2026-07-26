# frozen_string_literal: true

require "test_helper"

class CommunityPermissionRegressionMatrixTest < ActionDispatch::IntegrationTest
  ROLE_EXPECTATIONS = {
    anonymous: {
      public_topic: true,
      private_section: false,
      hidden_topic: false,
      pending_post: false,
      whisper: false,
      private_message: false,
      private_attachment: false,
      admin_route: false
    },
    member: {
      public_topic: true,
      private_section: false,
      hidden_topic: false,
      pending_post: false,
      whisper: false,
      private_message: true,
      private_attachment: false,
      admin_route: false
    },
    restricted_member: {
      public_topic: true,
      private_section: false,
      hidden_topic: false,
      pending_post: false,
      whisper: false,
      private_message: false,
      private_attachment: false,
      admin_route: false
    },
    moderator: {
      public_topic: true,
      private_section: true,
      hidden_topic: true,
      pending_post: true,
      whisper: true,
      private_message: false,
      private_attachment: true,
      admin_route: false
    },
    administrator: {
      public_topic: true,
      private_section: true,
      hidden_topic: true,
      pending_post: true,
      whisper: true,
      private_message: false,
      private_attachment: true,
      admin_route: true
    }
  }.freeze

  setup do
    suffix = SecureRandom.hex(5)
    @category = Community::Category.create!(
      name: "Permission matrix #{suffix}",
      slug: "permission-matrix-#{suffix}"
    )
    @public_section = Community::Section.create!(
      category: @category,
      name: "Public matrix section #{suffix}",
      slug: "public-matrix-#{suffix}",
      position: 0
    )
    @private_section = Community::Section.create!(
      category: @category,
      name: "Private matrix section #{suffix}",
      slug: "private-matrix-#{suffix}",
      position: 1,
      permissions: { "view" => [ "forum.permission_matrix.private" ] }
    )

    @author = create_user
    @member = create_user(forum_trust_level_override: 1)
    @restricted_member = create_user(forum_trust_level_override: 1)
    @moderator = create_user(account_type: "staff")
    @administrator = create_user(account_type: "admin")

    grant_permission(@moderator, "forum.permission_matrix.private")
    grant_permission(@administrator, "forum.permission_matrix.private")
    grant_permission(@administrator, "forum.topics.lock")
    grant_permission(@administrator, "admin.access")

    Community::SectionModerator.create!(section: @public_section, user: @moderator)
    Community::SectionModerator.create!(section: @private_section, user: @moderator)
    Community::UserSilence.create!(
      user: @restricted_member,
      created_by: @administrator,
      reason: "Permission matrix restricted member",
      expires_at: 1.day.from_now
    )

    @public_topic, @public_post = create_topic_with_post(
      section: @public_section,
      title: "Public matrix topic #{suffix}",
      body: "Public matrix body #{suffix}"
    )
    @private_topic, @private_post = create_topic_with_post(
      section: @private_section,
      title: "Private matrix topic #{suffix}",
      body: "Private matrix body #{suffix}"
    )
    @hidden_topic, @hidden_post = create_topic_with_post(
      section: @public_section,
      title: "Hidden matrix topic #{suffix}",
      body: "Hidden matrix body #{suffix}",
      topic_status: "hidden"
    )
    @moderation_topic, = create_topic_with_post(
      section: @public_section,
      title: "Moderation matrix topic #{suffix}",
      body: "Moderation matrix public body #{suffix}"
    )
    @pending_post = Community::Post.create!(
      topic: @moderation_topic,
      user: @author,
      floor_number: 2,
      body: "Pending matrix secret #{suffix}",
      status: "pending_approval"
    )
    @whisper = Community::Post.create!(
      topic: @moderation_topic,
      user: @moderator,
      floor_number: 3,
      body: "Whisper matrix secret #{suffix}",
      status: "published",
      post_type: "whisper"
    )

    @conversation = Community::Conversation.create!(
      creator: @author,
      title: "Private message matrix #{suffix}"
    )
    @conversation.participants.create!(user: @author)
    @conversation.participants.create!(user: @member)
    @message = @conversation.messages.create!(
      user: @author,
      body: "Private message matrix secret #{suffix}"
    )

    create_private_attachment!(suffix)
  end

  teardown do
    upload = @attachment&.upload_record
    if upload&.persisted?
      Community::CleanupUpload.call(upload: upload, force: true)
    elsif @attachment&.persisted? && @attachment.file.attached?
      @attachment.file.purge
    end
  end

  test "canonical policies match the five-role read matrix" do
    actors.each do |role, user|
      expected = ROLE_EXPECTATIONS.fetch(role)

      assert_equal expected[:public_topic],
        !!Community::ForumAccess.topic_visible?(topic: @public_topic, user: user),
        "#{role} public topic"
      assert_equal expected[:private_section],
        !!Community::SectionAccess.view?(section: @private_section, user: user),
        "#{role} private section"
      assert_equal expected[:hidden_topic],
        !!Community::ForumAccess.topic_visible?(topic: @hidden_topic, user: user),
        "#{role} hidden topic"
      assert_equal expected[:pending_post],
        !!Community::ForumAccess.post_visible?(post: @pending_post, user: user),
        "#{role} pending post"
      assert_equal expected[:whisper],
        !!Community::ForumAccess.post_visible?(post: @whisper, user: user),
        "#{role} whisper"
      assert_equal expected[:private_message],
        !!(user.present? && @conversation.participant?(user)),
        "#{role} private message"
      assert_equal expected[:private_attachment],
        !!Community::PostAttachmentAccess.downloadable?(@attachment, user: user),
        "#{role} private attachment"
      assert_equal expected[:admin_route],
        !!(user.present? && user.can_access_admin?),
        "#{role} admin route"
    end
  end

  test "aggregate scopes never leak hidden topics pending posts or whispers" do
    actors.each do |role, user|
      topic_ids = Community::ForumAccess.listed_topic_scope(
        relation: Community::Topic.where(id: [ @public_topic.id, @hidden_topic.id ]),
        user: user
      ).pluck(:id)
      post_ids = Community::ForumAccess.listed_post_scope(
        relation: Community::Post.where(id: [ @public_post.id, @pending_post.id, @whisper.id ]),
        user: user
      ).pluck(:id)

      assert_equal [ @public_topic.id ], topic_ids, "#{role} listed topics"
      assert_equal [ @public_post.id ], post_ids, "#{role} listed posts"
    end
  end

  test "web routes enforce the same matrix without privileged private-message bypass" do
    actors.each do |role, user|
      expected = ROLE_EXPECTATIONS.fetch(role)
      reset_actor_session!
      sign_in_as(user) if user

      get forum_topic_path(@private_topic)
      assert_response(expected[:private_section] ? :success : :not_found, "#{role} private topic route")

      get forum_topic_path(@hidden_topic)
      assert_response(expected[:hidden_topic] ? :success : :not_found, "#{role} hidden topic route")

      get forum_topic_path(@moderation_topic)
      assert_response :success
      assert_equal expected[:pending_post], response.body.include?(@pending_post.body),
        "#{role} pending post serialization"
      assert_equal expected[:whisper], response.body.include?(@whisper.body),
        "#{role} whisper serialization"

      get forum_conversation_path(@conversation)
      if role == :anonymous
        assert_redirected_to identity_sign_in_path
      else
        assert_response(expected[:private_message] ? :success : :not_found, "#{role} private message route")
      end

      get forum_attachment_path(@attachment)
      assert_response(expected[:private_attachment] ? :success : :forbidden, "#{role} attachment route")

      get admin_root_path
      if role == :anonymous
        assert_redirected_to identity_sign_in_path
      elsif expected[:admin_route]
        assert_response :success
      else
        assert_redirected_to root_path
      end
    end
  end

  test "restricted member stays readable but cannot publish or send private messages" do
    assert Community::ForumAccess.topic_visible?(topic: @public_topic, user: @restricted_member)

    reply = Community::CreatePost.call(
      user: @restricted_member,
      topic: @public_topic,
      body: "Restricted member must not publish",
      ip_address: "192.0.2.41",
      skip_interval_check: true
    )
    assert_predicate reply, :failure?
    assert_match(/silenced|禁言/i, reply.error)

    SiteSetting.set("forum.warning_block_pm_threshold", "1")
    Community::UserWarning.create!(
      user: @restricted_member,
      issuer: @administrator,
      reason: "Permission matrix PM restriction",
      points: 1,
      expires_at: 1.day.from_now
    )

    member_message = Community::CreateConversation.call(
      sender: @member,
      recipient_username: @author.username,
      body: "Normal member private message",
      ip_address: "192.0.2.42"
    )
    restricted_message = Community::CreateConversation.call(
      sender: @restricted_member,
      recipient_username: @author.username,
      body: "Restricted private message must not publish",
      ip_address: "192.0.2.43"
    )

    assert_predicate member_message, :success?
    assert_predicate restricted_message, :failure?
    assert_no_match(/Restricted private message must not publish/, Community::Message.pluck(:body).join("\n"))
  end

  private

  def actors
    {
      anonymous: nil,
      member: @member,
      restricted_member: @restricted_member,
      moderator: @moderator,
      administrator: @administrator
    }
  end

  def reset_actor_session!
    delete identity_session_path
    assert_response :redirect
  end

  def create_topic_with_post(section:, title:, body:, topic_status: "published")
    topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @author,
      title: title,
      status: topic_status,
      last_posted_at: Time.current,
      last_post_user: @author,
      replies_count: 0
    )
    post = Community::Post.create!(
      topic: topic,
      user: @author,
      floor_number: 1,
      body: body,
      status: "published"
    )
    [ topic, post ]
  end

  def create_private_attachment!(suffix)
    payload = "Private attachment matrix #{suffix}"
    @attachment = Community::PostAttachment.create!(
      post: @private_post,
      user: @author,
      filename: "permission-matrix-#{suffix}.txt",
      content_type: "text/plain",
      byte_size: payload.bytesize
    )
    @attachment.file.attach(
      io: StringIO.new(payload),
      filename: @attachment.filename,
      content_type: "text/plain",
      identify: false
    )
    mark_attachment_scan_clean!(@attachment)
  end
end
