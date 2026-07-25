# frozen_string_literal: true

require "test_helper"

class ForumContentIntegrityTest < ActiveSupport::TestCase
  setup do
    suffix = SecureRandom.hex(5)
    category = Community::Category.create!(
      name: "Integrity #{suffix}",
      slug: "integrity-#{suffix}"
    )
    @section = Community::Section.create!(
      category: category,
      name: "Integrity",
      slug: "integrity-#{suffix}",
      position: 0
    )
    @author = create_user(username: "integrity_author_#{suffix}")
    @moderator = create_user(username: "integrity_mod_#{suffix}")
    grant_permission(@moderator, "forum.topics.move")
    grant_permission(@moderator, "forum.topics.lock")
    @topic = create_topic(title: "Integrity source")
    @opening_post = create_post(topic: @topic, floor: 1, body: "Opening post")
  end

  test "new replies never reuse a soft-deleted floor" do
    deleted_reply = create_post(topic: @topic, floor: 2, body: "Deleted reply")
    deleted_reply.soft_delete!
    Community::SyncTopicLastPost.call(topic: @topic)

    result = Community::CreatePost.call(
      user: @author,
      topic: @topic,
      body: "Replacement reply",
      skip_interval_check: true
    )

    assert result.success?, result.error
    assert_equal 3, result.value.floor_number
    assert_equal [ 1, 2, 3 ],
      Community::Post.with_discarded.where(forum_topic_id: @topic.id).order(:floor_number).pluck(:floor_number)
    assert_equal 1, @topic.reload.replies_count
    assert_equal result.value.id, @topic.posts.countable.order(:floor_number).last.id
  end

  test "counter synchronization clears stale last-post pointers when no public post remains" do
    @opening_post.update!(status: "hidden")

    result = Community::SyncTopicLastPost.call(topic: @topic)

    assert result.success?
    assert_equal 0, @topic.reload.replies_count
    assert_nil @topic.last_posted_at
    assert_nil @topic.last_post_user_id
  end

  test "post deletion rolls back when counter synchronization fails" do
    reply = create_post(topic: @topic, floor: 2, body: "Must survive rollback")
    @topic.update_column(:title, "")

    result = Community::DeletePost.call(actor: @moderator, post: reply)

    assert result.failure?
    assert_nil reply.reload.deleted_at
    assert_equal 1, @topic.reload.replies_count
  end

  test "splitting a solved reply clears the source solved-post pointer" do
    split_post = create_post(topic: @topic, floor: 2, body: "Split starts here")
    solved_post = create_post(topic: @topic, floor: 3, body: "Accepted answer")
    @topic.update!(solved_post: solved_post)

    result = Community::SplitTopic.call(
      user: @moderator,
      topic: @topic,
      post: split_post,
      title: "Split destination"
    )

    assert result.success?, result.error
    assert_nil @topic.reload.solved_post_id
    assert_equal result.value.id, solved_post.reload.forum_topic_id
    assert_equal [ 1, 2 ], result.value.posts.order(:floor_number).pluck(:floor_number)
    assert_equal 1, result.value.reload.replies_count
  end

  test "merge preserves deleted floors and repairs source pointers and counters" do
    deleted_reply = create_post(topic: @topic, floor: 2, body: "Deleted source reply")
    deleted_reply.update!(parent_post: @opening_post)
    deleted_reply.soft_delete!
    live_reply = create_post(topic: @topic, floor: 3, body: "Live source reply")
    live_reply.update!(parent_post: deleted_reply)
    @topic.update!(solved_post: live_reply)

    target = create_topic(title: "Merge target")
    target_opening = create_post(topic: target, floor: 1, body: "Target opening")
    target_deleted = create_post(topic: target, floor: 2, body: "Deleted target reply")
    target_deleted.soft_delete!

    result = Community::MergeTopics.call(
      user: @moderator,
      source: @topic,
      target_public_id: target.public_id
    )

    assert result.success?, result.error
    assert_equal [ 1, 2, 3, 4 ],
      Community::Post.with_discarded.where(forum_topic_id: target.id).order(:floor_number).pluck(:floor_number)
    assert_equal target.id, deleted_reply.reload.forum_topic_id
    assert_equal 3, deleted_reply.floor_number
    assert deleted_reply.deleted_at.present?
    assert_nil deleted_reply.parent_post_id
    assert_equal target.id, live_reply.reload.forum_topic_id
    assert_equal 4, live_reply.floor_number
    assert_equal deleted_reply.id, live_reply.parent_post_id
    assert_equal "hidden", @topic.reload.status
    assert_nil @topic.solved_post_id
    assert_equal 0, @topic.replies_count
    assert_equal @opening_post.id, @topic.posts.countable.last.id
    assert_equal 1, target.reload.replies_count
    assert_equal live_reply.id, target.posts.countable.order(:floor_number).last.id
    assert_equal live_reply.user_id, target.last_post_user_id
    assert_equal target_opening.id, target.posts.find_by!(floor_number: 1).id
  end

  test "merge rolls every moved row back when final counter synchronization fails" do
    source_reply = create_post(topic: @topic, floor: 2, body: "Rollback source reply")
    target = create_topic(title: "Invalid merge target")
    create_post(topic: target, floor: 1, body: "Target opening")
    target.update_column(:title, "")

    result = Community::MergeTopics.call(
      user: @moderator,
      source: @topic,
      target_public_id: target.public_id
    )

    assert result.failure?
    assert_equal "published", @topic.reload.status
    assert_not @topic.locked?
    assert_equal @topic.id, source_reply.reload.forum_topic_id
    assert_equal 2, source_reply.floor_number
    assert_equal [ 1 ], target.reload.posts.order(:floor_number).pluck(:floor_number)
  end

  test "split carries soft-deleted rows without reusing their positions" do
    split_post = create_post(topic: @topic, floor: 2, body: "New opening")
    deleted_reply = create_post(topic: @topic, floor: 3, body: "Deleted middle")
    deleted_reply.soft_delete!
    live_reply = create_post(topic: @topic, floor: 4, body: "Visible tail")

    result = Community::SplitTopic.call(
      user: @moderator,
      topic: @topic,
      post: split_post,
      title: "Split with deleted row"
    )

    assert result.success?, result.error
    new_topic = result.value
    assert_equal [ 1, 2, 3 ],
      Community::Post.with_discarded.where(forum_topic_id: new_topic.id).order(:floor_number).pluck(:floor_number)
    assert_equal new_topic.id, deleted_reply.reload.forum_topic_id
    assert_equal 2, deleted_reply.floor_number
    assert deleted_reply.deleted_at.present?
    assert_equal 3, live_reply.reload.floor_number
    assert_equal 1, new_topic.reload.replies_count
    assert_equal live_reply.id, new_topic.posts.countable.order(:floor_number).last.id
    assert_equal live_reply.user_id, new_topic.last_post_user_id
  end

  private

  def create_topic(title:)
    Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @author,
      title: title,
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @author,
      replies_count: 0
    )
  end

  def create_post(topic:, floor:, body:)
    Community::Post.create!(
      topic: topic,
      user: @author,
      floor_number: floor,
      body: body,
      status: "published"
    )
  end
end
