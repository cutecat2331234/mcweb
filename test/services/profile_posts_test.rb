# frozen_string_literal: true

require "test_helper"

class CreateProfilePostTest < ActiveSupport::TestCase
  setup do
    @author = create_user
    @owner = create_user
    SiteSetting.set("forum.profile_posts_enabled", "true")
    SiteSetting.set("forum.min_trust_level_profile_post", "0")
  end

  test "creates a profile post and notifies the wall owner" do
    assert_difference -> { Community::ProfilePost.count } => 1,
                      -> { @owner.notifications.where(notification_type: "forum.profile_post").count } => 1 do
      result = Community::CreateProfilePost.call(author: @author, profile_user: @owner, body: "Hello wall")
      assert result.success?, result.error
    end
    post = Community::ProfilePost.last
    assert_equal @author.id, post.user_id
    assert_equal @owner.id, post.profile_user_id
    assert_equal "published", post.status
  end

  test "posting on your own wall does not notify yourself" do
    assert_no_difference -> { @author.notifications.count } do
      result = Community::CreateProfilePost.call(author: @author, profile_user: @author, body: "my status")
      assert result.success?, result.error
    end
  end

  test "rejects a blank body" do
    result = Community::CreateProfilePost.call(author: @author, profile_user: @owner, body: "   ")
    assert result.failure?
    assert_equal "profile_post_blank", result.error
  end

  test "is blocked when the wall owner has blocked the author" do
    Community::UserBlock.create!(blocker: @owner, blocked: @author)
    result = Community::CreateProfilePost.call(author: @author, profile_user: @owner, body: "hi")
    assert result.failure?
    assert_equal "profile_post_not_allowed", result.error
  end

  test "enforces the minimum trust level" do
    SiteSetting.set("forum.min_trust_level_profile_post", "2")
    result = Community::CreateProfilePost.call(author: @author, profile_user: @owner, body: "hi")
    assert result.failure?
    assert_equal "profile_post_not_allowed", result.error
  end

  test "respects the disabled feature flag" do
    SiteSetting.set("forum.profile_posts_enabled", "false")
    result = Community::CreateProfilePost.call(author: @author, profile_user: @owner, body: "hi")
    assert result.failure?
    assert_equal "profile_posts_disabled", result.error
  end
end

class CreateProfilePostCommentTest < ActiveSupport::TestCase
  setup do
    @author = create_user
    @owner = create_user
    @commenter = create_user
    SiteSetting.set("forum.min_trust_level_profile_post", "0")
    @post = Community::CreateProfilePost.call(author: @author, profile_user: @owner, body: "wall post").value
  end

  test "creates a comment and notifies both the post author and the wall owner" do
    assert_difference -> { Community::ProfilePostComment.count }, 1 do
      result = Community::CreateProfilePostComment.call(author: @commenter, profile_post: @post, body: "nice")
      assert result.success?, result.error
    end
    assert_equal 1, @author.notifications.where(notification_type: "forum.profile_post_comment").count
    assert_equal 1, @owner.notifications.where(notification_type: "forum.profile_post_comment").count
    assert_equal 0, @commenter.notifications.where(notification_type: "forum.profile_post_comment").count
  end

  test "cannot comment on a hidden profile post" do
    @post.update!(status: :hidden)
    result = Community::CreateProfilePostComment.call(author: @commenter, profile_post: @post, body: "hi")
    assert result.failure?
  end
end

class ProfilePostsFlowTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user
    @author = create_user
    SiteSetting.set("forum.min_trust_level_profile_post", "0")
  end

  test "posting on a profile wall over HTTP creates a post and redirects" do
    sign_in_as(@author)
    assert_difference -> { Community::ProfilePost.count }, 1 do
      post forum_user_profile_posts_path(@owner.username), params: { profile_post: { body: "Welcome!" } }
    end
    assert_redirected_to forum_user_path(@owner.username)
    record = Community::ProfilePost.last
    assert_equal @author.id, record.user_id
    assert_equal @owner.id, record.profile_user_id
  end

  test "the author can soft-delete their own profile post" do
    pp = Community::CreateProfilePost.call(author: @author, profile_user: @owner, body: "x").value
    sign_in_as(@author)
    delete forum_profile_post_path(pp.id)
    assert_redirected_to forum_user_path(@owner.username)
    assert_not Community::ProfilePost.exists?(pp.id), "soft-deleted post should be excluded by the default scope"
  end
end
