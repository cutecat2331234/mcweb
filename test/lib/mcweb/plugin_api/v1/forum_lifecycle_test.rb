# frozen_string_literal: true

require "test_helper"
require "mcweb/plugin_api/v1/forum"

class Mcweb::PluginApi::V1::ForumLifecycleTest < ActiveSupport::TestCase
  setup do
    suffix = SecureRandom.hex(5)
    @category = Community::Category.create!(
      name: "Plugin lifecycle #{suffix}",
      slug: "plugin-lifecycle-#{suffix}"
    )
    @source_section = Community::Section.create!(
      category: @category,
      name: "Source",
      slug: "plugin-lifecycle-source-#{suffix}",
      position: 0
    )
    @target_section = Community::Section.create!(
      category: @category,
      name: "Target",
      slug: "plugin-lifecycle-target-#{suffix}",
      position: 1
    )
    @private_section = Community::Section.create!(
      category: @category,
      name: "Private",
      slug: "plugin-lifecycle-private-#{suffix}",
      position: 2,
      permissions: { "view" => [ "forum.plugin_lifecycle.private" ] }
    )
    @author = create_user(forum_trust_level_override: 1)
    @member = create_user
    @staff = create_user
    grant_permission(@staff, "forum.topics.lock")
    grant_permission(@staff, "forum.topics.move")
    grant_permission(@staff, "forum.plugin_lifecycle.private")
    @section_moderator = create_user
    Community::SectionModerator.create!(section: @source_section, user: @section_moderator)
    Community::SectionModerator.create!(section: @target_section, user: @section_moderator)

    @topic, @opening_post, @reply, @last_reply = create_topic_with_posts(
      section: @source_section,
      user: @author,
      title: "Plugin lifecycle source"
    )
    @forum = Mcweb::PluginApi::V1::Forum.new
  end

  test "move and copy use core moderation services and current target visibility" do
    denied = @forum.move_topic(
      user: @member,
      topic_id: @topic.id,
      section_id: @target_section.id
    )
    assert_predicate denied, :failure?
    assert_equal "service_failure", denied.code

    moved = @forum.move_topic(
      user: @staff,
      topic_public_id: @topic.public_id,
      section_slug: @target_section.slug,
      leave_redirect: true
    )
    assert_predicate moved, :success?
    assert_equal @target_section.id, moved.value.fetch("section_id")
    assert_equal @target_section.id, @topic.reload.forum_section_id
    assert Community::Topic.exists?(
      forum_section_id: @source_section.id,
      redirect_to_topic_id: @topic.id
    )

    copied = @forum.copy_topic(
      user: @staff,
      topic_id: @topic.id,
      section_id: @source_section.id
    )
    assert_predicate copied, :success?
    copied_topic = Community::Topic.find(copied.value.fetch("id"))
    assert_equal @source_section.id, copied_topic.forum_section_id
    assert_equal @topic.posts.where(status: "published").count, copied_topic.posts.count

    revoke_permission(@staff, "forum.plugin_lifecycle.private")
    assert_not_visible @forum.copy_topic(
      user: @staff,
      topic_id: @topic.id,
      section_id: @private_section.id
    )
  end

  test "merge preauthorizes both topics and returns the core target snapshot" do
    target, = create_topic_with_posts(
      section: @target_section,
      user: @author,
      title: "Plugin lifecycle merge target",
      reply_count: 0
    )

    merged = @forum.merge_topics(
      user: @staff,
      source_topic_id: @topic.id,
      target_topic_public_id: target.public_id
    )
    assert_predicate merged, :success?
    assert_equal target.id, merged.value.fetch("id")
    assert_equal "hidden", @topic.reload.status
    assert @topic.locked?
    assert_equal 3, target.reload.posts.count

    private_topic, = create_topic_with_posts(
      section: @private_section,
      user: @author,
      title: "Plugin lifecycle private merge",
      reply_count: 0
    )
    revoke_permission(@staff, "forum.plugin_lifecycle.private")
    assert_not_visible @forum.merge_topics(
      user: @staff,
      source_topic_id: target.id,
      target_topic_id: private_topic.id
    )
  end

  test "split validates the source post and delegates floor reassignment" do
    split = @forum.split_topic(
      user: @staff,
      topic_id: @topic.id,
      post_id: @reply.id,
      title: "Split through plugin API",
      section_id: @target_section.id
    )
    assert_predicate split, :success?
    split_topic = Community::Topic.find(split.value.fetch("id"))
    assert_equal @target_section.id, split_topic.forum_section_id
    assert_equal "Split through plugin API", split_topic.title
    assert_equal [ 1, 2 ], split_topic.posts.order(:floor_number).pluck(:floor_number)
    assert_equal [ @reply.id, @last_reply.id ], split_topic.posts.order(:floor_number).pluck(:id)
    assert_equal [ @opening_post.id ], @topic.reload.posts.pluck(:id)

    opening_post_failure = @forum.split_topic(
      user: @staff,
      topic_id: @topic.id,
      post_id: @opening_post.id
    )
    assert_predicate opening_post_failure, :failure?
    assert_equal "service_failure", opening_post_failure.code
  end

  test "post delete restore approval rejection and moderation stay core authorized" do
    deleted = @forum.delete_post(user: @author, id: @reply.id)
    assert_predicate deleted, :success?
    assert deleted.value.fetch("deleted_at")
    assert @reply.reload.deleted_at

    assert_not_visible @forum.restore_post(user: @author, id: @reply.id)
    restored = @forum.restore_post(user: @staff, id: @reply.id)
    assert_predicate restored, :success?
    assert_nil restored.value.fetch("deleted_at")
    assert_nil @reply.reload.deleted_at

    pending_approved = Community::Post.create!(
      topic: @topic,
      user: @author,
      floor_number: 4,
      body: "Pending approval",
      status: "pending_approval"
    )
    approved = @forum.approve_post(user: @staff, id: pending_approved.id)
    assert_predicate approved, :success?
    assert_equal "published", approved.value.fetch("status")

    pending_rejected = Community::Post.create!(
      topic: @topic,
      user: @author,
      floor_number: 5,
      body: "Pending rejection",
      status: "pending_approval"
    )
    rejected = @forum.reject_post(
      user: @staff,
      id: pending_rejected.id,
      reason: "Policy"
    )
    assert_predicate rejected, :success?
    assert_equal "hidden", rejected.value.fetch("status")

    hidden = @forum.moderate_post(
      user: @staff,
      id: @last_reply.id,
      action: "hide"
    )
    assert_predicate hidden, :success?
    assert_equal "hidden", hidden.value.fetch("status")

    locked = @forum.moderate_topic(
      user: @section_moderator,
      topic_id: @topic.id,
      action: "lock",
      lock_reason: "Review"
    )
    assert_predicate locked, :success?
    assert locked.value.fetch("locked")

    global_only = @forum.moderate_topic(
      user: @section_moderator,
      topic_id: @topic.id,
      action: "feature"
    )
    assert_predicate global_only, :failure?
    assert_equal "service_failure", global_only.code

    invalid = @forum.moderate_post(
      user: @staff,
      id: @last_reply.id,
      action: "destroy"
    )
    assert_equal "invalid_argument", invalid.code
  end

  test "private moderation targets are closed immediately after permission revocation" do
    private_topic, _opening, private_reply = create_topic_with_posts(
      section: @private_section,
      user: @author,
      title: "Plugin private moderation",
      reply_count: 1
    )
    deleted = @forum.delete_post(user: @staff, id: private_reply.id)
    assert_predicate deleted, :success?

    revoke_permission(@staff, "forum.plugin_lifecycle.private")
    assert_not_visible @forum.restore_post(user: @staff, id: private_reply.id)
    assert_not_visible @forum.moderate_topic(
      user: @staff,
      topic_id: private_topic.id,
      action: "lock"
    )
  end

  test "poll snapshots hide results until voting and mutations reuse poll services" do
    poll = Community::Poll.create!(
      topic: @topic,
      question: "Which release?",
      options: [ "Stable", "Preview" ],
      hide_results_until_vote: true
    )

    initial = @forum.find_poll(user: @member, id: poll.id)
    assert_predicate initial, :success?
    refute initial.value.fetch("show_results")
    assert_empty initial.value.fetch("results")

    voted = @forum.vote_poll(user: @member, id: poll.id, option_index: 1)
    assert_predicate voted, :success?
    assert voted.value.fetch("show_results")
    assert_equal [ 1 ], voted.value.fetch("viewer_vote_indices")
    assert_equal 1, voted.value.fetch("total_votes")

    topic_poll = @forum.topic_poll(user: @member, topic_id: @topic.id)
    assert_equal poll.id, topic_poll.value.fetch("id")

    revoked = @forum.revoke_poll_vote(user: @member, id: poll.id)
    assert_predicate revoked, :success?
    refute revoked.value.fetch("show_results")
    assert_empty revoked.value.fetch("viewer_vote_indices")

    closed = @forum.close_poll(user: @author, id: poll.id)
    assert_predicate closed, :success?
    refute closed.value.fetch("open")
    assert closed.value.fetch("show_results")
  end

  test "poll reads and writes recheck private section permission" do
    private_topic, = create_topic_with_posts(
      section: @private_section,
      user: @author,
      title: "Plugin private poll",
      reply_count: 0
    )
    poll = Community::Poll.create!(
      topic: private_topic,
      question: "Private?",
      options: %w[Yes No]
    )

    assert_predicate @forum.find_poll(user: @staff, id: poll.id), :success?
    revoke_permission(@staff, "forum.plugin_lifecycle.private")
    assert_not_visible @forum.find_poll(user: @staff, id: poll.id)
    assert_not_visible @forum.vote_poll(
      user: @staff,
      id: poll.id,
      option_index: 0
    )
  end

  test "topic field definition and value reads use core serialization and visibility" do
    definition = Community::TopicFieldDefinition.create!(
      key: "plugin_release_channel_#{SecureRandom.hex(3)}",
      label: "Release channel",
      field_type: "select",
      display_location: "before_message",
      choices: "Stable\nPreview",
      section_ids: [ @source_section.id ],
      active: true,
      editable_by_user: true,
      owner_plugin_id: "acme/release"
    )
    Community::TopicFieldValue.create!(
      topic: @topic,
      definition:,
      value: "Stable"
    )

    definitions = @forum.topic_field_definitions(
      user: @member,
      section_id: @source_section.id
    )
    field_definition = definitions.value.find { |value| value.fetch("key") == definition.key }
    assert_equal "forum.topic_field_definition", field_definition.fetch("type")
    assert_equal [ "Stable", "Preview" ], field_definition.fetch("choices")
    anonymous_definition = @forum.topic_field_definitions(
      user: nil,
      section_id: @source_section.id
    ).value.find { |value| value.fetch("key") == definition.key }
    refute anonymous_definition.fetch("editable")

    fields = @forum.topic_fields(user: @member, topic_id: @topic.id)
    field = fields.value.find { |value| value.fetch("key") == definition.key }
    assert_equal "forum.topic_field", field.fetch("type")
    assert_equal "Stable", field.fetch("raw_value")
    assert_equal "Stable", field.fetch("display_value")

    private_topic, = create_topic_with_posts(
      section: @private_section,
      user: @author,
      title: "Plugin private fields",
      reply_count: 0
    )
    revoke_permission(@staff, "forum.plugin_lifecycle.private")
    assert_not_visible @forum.topic_field_definitions(
      user: @staff,
      section_id: @private_section.id
    )
    assert_not_visible @forum.topic_fields(
      user: @staff,
      topic_id: private_topic.id
    )
  end

  test "attachment metadata and linking never bypass ownership or post visibility" do
    uploaded = @forum.create_attachment(
      user: @author,
      file: uploaded_file("plugin-notes.txt", "text/plain", "plugin attachment")
    )
    assert_predicate uploaded, :success?
    attachment_id = uploaded.value.fetch("id")
    refute_includes uploaded.value.keys, "key"
    refute_includes uploaded.value.keys, "checksum"
    assert_nil uploaded.value.fetch("post_id")

    assert_not_visible @forum.find_attachment(user: @member, id: attachment_id)
    assert_equal [ attachment_id ], @forum.unlinked_attachments(
      user: @author
    ).value.pluck("id")

    linked = @forum.sync_post_attachments(
      user: @author,
      post_id: @reply.id,
      attachment_ids: [ attachment_id ]
    )
    assert_predicate linked, :success?
    assert linked.value.fetch("changed")
    assert_equal [ attachment_id ], linked.value.fetch("attachments").pluck("id")
    assert_equal @reply.id, Community::PostAttachment.find(attachment_id).forum_post_id

    visible = @forum.find_attachment(user: @member, id: attachment_id)
    assert_predicate visible, :success?
    assert_equal [ attachment_id ], @forum.post_attachments(
      user: @member,
      post_id: @reply.id
    ).value.pluck("id")

    unauthorized = @forum.sync_post_attachments(
      user: @member,
      post_id: @reply.id,
      attachment_ids: []
    )
    assert_predicate unauthorized, :failure?
    assert_equal "service_failure", unauthorized.code
    assert_equal @reply.id, Community::PostAttachment.find(attachment_id).forum_post_id
  end

  test "linked private attachment metadata disappears after permission revocation" do
    private_topic, _opening, private_reply = create_topic_with_posts(
      section: @private_section,
      user: @staff,
      title: "Plugin private attachment",
      reply_count: 1
    )
    uploaded = @forum.create_attachment(
      user: @staff,
      file: uploaded_file("private.txt", "text/plain", "private attachment")
    )
    attachment_id = uploaded.value.fetch("id")
    linked = @forum.sync_post_attachments(
      user: @staff,
      post_id: private_reply.id,
      attachment_ids: [ attachment_id ]
    )
    assert_predicate linked, :success?

    revoke_permission(@staff, "forum.plugin_lifecycle.private")
    assert_not_visible @forum.find_attachment(user: @staff, id: attachment_id)
    assert_not_visible @forum.post_attachments(
      user: @staff,
      post_id: private_reply.id
    )
    assert_not_visible @forum.moderate_topic(
      user: @staff,
      topic_id: private_topic.id,
      action: "lock"
    )
  end

  test "lifecycle poll field and attachment selectors reject ambiguous or invalid input" do
    invalid_results = [
      @forum.move_topic(
        user: @staff,
        topic_id: @topic.id,
        topic_public_id: @topic.public_id,
        section_id: @target_section.id
      ),
      @forum.move_topic(
        user: @staff,
        topic_id: @topic.id,
        section_id: @target_section.id,
        section_slug: @target_section.slug
      ),
      @forum.move_topic(
        user: @staff,
        topic_id: @topic.id,
        section_id: @target_section.id,
        leave_redirect: "yes"
      ),
      @forum.merge_topics(
        user: @staff,
        source_topic_id: @topic.id,
        source_topic_public_id: @topic.public_id,
        target_topic_id: @topic.id
      ),
      @forum.split_topic(
        user: @staff,
        topic_id: @topic.id,
        topic_public_id: @topic.public_id,
        post_id: @reply.id
      ),
      @forum.find_poll(user: @member, id: 0),
      @forum.topic_poll(
        user: @member,
        topic_id: @topic.id,
        topic_public_id: @topic.public_id
      ),
      @forum.topic_field_definitions(
        user: @member,
        section_id: @source_section.id,
        section_slug: @source_section.slug
      ),
      @forum.find_attachment(user: @member, id: -1),
      @forum.post_attachments(
        user: @member,
        post_id: @reply.id,
        limit: Mcweb::PluginApi::V1::Forum::MAX_LIMIT + 1
      )
    ]

    invalid_results.each do |result|
      assert_predicate result, :failure?
      assert_equal "invalid_argument", result.code
      assert_predicate result, :frozen?
    end
  end

  test "lifecycle methods audit read write and moderation capabilities exactly once" do
    audits = []
    forum = Mcweb::PluginApi::V1::Forum.new(
      capability_auditor: ->(capability) { audits << capability }
    )
    invalid_user = Object.new

    operations = {
      "forum.moderate" => [
        -> { forum.move_topic(user: invalid_user, topic_id: 1, section_id: 2) },
        -> { forum.copy_topic(user: invalid_user, topic_id: 1, section_id: 2) },
        lambda {
          forum.merge_topics(
            user: invalid_user,
            source_topic_id: 1,
            target_topic_id: 2
          )
        },
        -> { forum.split_topic(user: invalid_user, topic_id: 1, post_id: 2) },
        -> { forum.delete_post(user: invalid_user, id: 1) },
        -> { forum.restore_post(user: invalid_user, id: 1) },
        -> { forum.approve_post(user: invalid_user, id: 1) },
        -> { forum.reject_post(user: invalid_user, id: 1) },
        -> { forum.moderate_topic(user: invalid_user, topic_id: 1, action: "lock") },
        -> { forum.moderate_post(user: invalid_user, id: 1, action: "hide") }
      ],
      "forum.read" => [
        -> { forum.find_poll(user: invalid_user, id: 1) },
        -> { forum.topic_poll(user: invalid_user, topic_id: 1) },
        -> { forum.topic_field_definitions(user: invalid_user, section_id: 1) },
        -> { forum.topic_custom_fields(user: invalid_user, topic_id: 1) },
        -> { forum.topic_fields(user: invalid_user, topic_id: 1) },
        -> { forum.find_attachment(user: invalid_user, id: 1) },
        -> { forum.post_attachments(user: invalid_user, post_id: 1) },
        -> { forum.unlinked_attachments(user: invalid_user) }
      ],
      "forum.write" => [
        -> { forum.vote_poll(user: invalid_user, id: 1, option_index: 0) },
        -> { forum.revoke_poll_vote(user: invalid_user, id: 1) },
        -> { forum.close_poll(user: invalid_user, id: 1) },
        -> { forum.create_attachment(user: invalid_user, file: nil) },
        -> { forum.sync_post_attachments(user: invalid_user, post_id: 1, attachment_ids: []) }
      ]
    }

    operations.each do |capability, calls|
      calls.each do |operation|
        audits.clear
        result = operation.call
        assert_predicate result, :failure?
        assert_equal "invalid_user", result.code
        assert_equal [ capability ], audits
      end
    end
  end

  test "poll field attachment and lifecycle snapshots are deeply immutable" do
    poll = Community::Poll.create!(
      topic: @topic,
      question: "Immutable?",
      options: %w[Yes No]
    )
    definition = Community::TopicFieldDefinition.create!(
      key: "plugin_immutable_#{SecureRandom.hex(3)}",
      label: "Immutable",
      field_type: "text",
      display_location: "before_message",
      section_ids: [ @source_section.id ],
      active: true,
      editable_by_user: true
    )
    Community::TopicFieldValue.create!(topic: @topic, definition:, value: "Value")
    uploaded = @forum.create_attachment(
      user: @author,
      file: uploaded_file("immutable.txt", "text/plain", "immutable")
    )
    attachment_id = uploaded.value.fetch("id")
    sync = @forum.sync_post_attachments(
      user: @author,
      post_id: @reply.id,
      attachment_ids: [ attachment_id ]
    )

    results = [
      @forum.find_poll(user: @member, id: poll.id),
      @forum.topic_field_definitions(user: @member, section_id: @source_section.id),
      @forum.topic_fields(user: @member, topic_id: @topic.id),
      @forum.find_attachment(user: @member, id: attachment_id),
      sync,
      @forum.moderate_topic(user: @staff, topic_id: @topic.id, action: "pin")
    ]
    results.each do |result|
      assert_predicate result, :success?
      assert_deeply_frozen(result.to_h)
      refute_contains_active_record(result.to_h)
    end
    assert_raises(FrozenError) do
      results.first.value.fetch("options").first["label"] = "Changed"
    end
    assert_raises(FrozenError) do
      sync.value.fetch("attachments") << {}
    end
  end

  private

  def create_topic_with_posts(section:, user:, title:, reply_count: 2)
    topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section:,
      user:,
      title:,
      status: "published",
      last_posted_at: Time.current,
      last_post_user: user,
      replies_count: 0
    )
    posts = [
      Community::Post.create!(
        topic:,
        user:,
        floor_number: 1,
        body: "#{title} opening",
        status: "published"
      )
    ]
    reply_count.times do |index|
      posts << Community::Post.create!(
        topic:,
        user:,
        floor_number: index + 2,
        body: "#{title} reply #{index + 1}",
        status: "published"
      )
    end
    [ topic, *posts ]
  end

  def uploaded_file(name, content_type, content)
    tempfile = Tempfile.new([ File.basename(name, ".*"), File.extname(name) ])
    tempfile.write(content)
    tempfile.rewind
    ActionDispatch::Http::UploadedFile.new(
      tempfile:,
      filename: name,
      type: content_type
    )
  end

  def revoke_permission(user, permission_key)
    role = Role.find_by!(key: "test_#{permission_key.tr('.', '_')}")
    user.roles.delete(role)
  end

  def assert_not_visible(result)
    assert_predicate result, :failure?
    assert_equal "not_found", result.code
    assert_match(/not found or not visible/, result.error)
  end

  def assert_deeply_frozen(value)
    assert_predicate value, :frozen?
    case value
    when Hash
      value.each do |key, item|
        assert_predicate key, :frozen?
        assert_deeply_frozen(item)
      end
    when Array
      value.each { |item| assert_deeply_frozen(item) }
    end
  end

  def refute_contains_active_record(value)
    refute_kind_of ActiveRecord::Base, value
    case value
    when Hash
      value.each do |key, item|
        refute_contains_active_record(key)
        refute_contains_active_record(item)
      end
    when Array
      value.each { |item| refute_contains_active_record(item) }
    end
  end
end
