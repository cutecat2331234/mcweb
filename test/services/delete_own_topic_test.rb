# frozen_string_literal: true

require "test_helper"

class DeleteOwnTopicTest < ActiveSupport::TestCase
  setup do
    DataGovernance::RetentionPolicy.ensure_defaults!
    @author = create_user
    @other = create_user
    suffix = SecureRandom.hex(5)
    category = Community::Category.create!(
      name: "Author deletion #{suffix}",
      slug: "author-deletion-#{suffix}"
    )
    @section = Community::Section.create!(
      category: category,
      name: "Author deletion",
      slug: "author-deletion-#{suffix}",
      position: 0
    )
    @topic = create_topic
  end

  test "the author can soft-delete a normal topic containing only their own posts" do
    create_post(user: @author, floor: 2, body: "Author follow-up")

    result = Community::DeleteOwnTopic.call(
      user: @author,
      topic: @topic,
      request_id: "topic-delete-#{SecureRandom.uuid}"
    )

    assert_predicate result, :success?, result.error
    refute Community::Topic.exists?(@topic.id)
    discarded = Community::Topic.with_discarded.find(@topic.id)
    assert_predicate discarded, :soft_deleted?
    lifecycle = DataGovernance::ContentLifecycleRecord.find_by!(
      target_type: "Community::Topic",
      target_id: @topic.id
    )
    assert_equal "soft_deleted", lifecycle.status
    assert_equal @author.id, lifecycle.deleted_by_id
    assert AuditLog.by_action("data_governance.content_soft_deleted")
      .where(resource_type: "Community::Topic", resource_id: @topic.id)
      .exists?
  end

  test "any other-user reply blocks author deletion even when the reply is not public" do
    create_post(user: @other, floor: 2, body: "Pending reply", status: "pending_approval")

    result = Community::DeleteOwnTopic.call(user: @author, topic: @topic)

    assert_predicate result, :failure?
    assert_equal "topic_delete_has_replies", result.code
    assert Community::Topic.exists?(@topic.id)
  end

  test "a retained soft-deleted reply from another user still blocks topic deletion" do
    reply = create_post(user: @other, floor: 2, body: "Retained deleted reply")
    reply.soft_delete!

    result = Community::DeleteOwnTopic.call(user: @author, topic: @topic)

    assert_predicate result, :failure?
    assert_equal "topic_delete_has_replies", result.code
    assert Community::Topic.exists?(@topic.id)
  end

  test "another user's retained staff whisper marks the topic as staff managed" do
    whisper = create_post(
      user: @other,
      floor: 2,
      body: "Private staff evidence",
      post_type: "whisper"
    )
    whisper.soft_delete!

    result = Community::DeleteOwnTopic.call(user: @author, topic: @topic)

    assert_predicate result, :failure?
    assert_equal "topic_delete_staff_managed", result.code
    assert Community::Topic.exists?(@topic.id)
  end

  test "a site small action marks the topic as staff managed" do
    create_post(
      user: @other,
      floor: 2,
      body: "Topic was moved by staff",
      post_type: "small_action"
    )

    result = Community::DeleteOwnTopic.call(user: @author, topic: @topic)

    assert_predicate result, :failure?
    assert_equal "topic_delete_staff_managed", result.code
    assert Community::Topic.exists?(@topic.id)
  end

  test "staff-managed topics and unresolved reports are evidence protected" do
    @topic.update!(pinned: true)
    staff_result = Community::DeleteOwnTopic.call(user: @author, topic: @topic)
    assert_predicate staff_result, :failure?
    assert_equal "topic_delete_staff_managed", staff_result.code

    @topic.update!(pinned: false)
    Community::Report.create!(
      reporter: @other,
      reportable: @topic,
      reason: "Requires moderator review",
      status: "pending"
    )
    report_result = Community::DeleteOwnTopic.call(user: @author, topic: @topic)
    assert_predicate report_result, :failure?
    assert_equal "topic_delete_evidence_protected", report_result.code
    assert Community::Topic.exists?(@topic.id)
  end

  private

  def create_topic
    topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @author,
      title: "Author-owned topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @author,
      replies_count: 0
    )
    Community::Post.create!(
      topic: topic,
      user: @author,
      floor_number: 1,
      body: "Opening post",
      status: "published"
    )
    topic.reload
  end

  def create_post(user:, floor:, body:, status: "published", post_type: "regular")
    Community::Post.create!(
      topic: @topic,
      user: user,
      floor_number: floor,
      body: body,
      status: status,
      post_type: post_type
    )
  end
end
