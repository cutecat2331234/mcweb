# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

class EditPostConcurrencyTest < ActionDispatch::IntegrationTest
  include InertiaRails::Minitest

  setup do
    suffix = SecureRandom.hex(5)
    category = Community::Category.create!(name: "Post revision #{suffix}", slug: "post-revision-#{suffix}")
    section = Community::Section.create!(
      category: category,
      name: "Post revision",
      slug: "post-revision-#{suffix}",
      position: 0
    )
    @author = create_user(username: "post_revision_author_#{suffix}")
    @other = create_user(username: "post_revision_other_#{suffix}")
    @topic = Community::CreateTopic.call(
      user: @author,
      section: section,
      title: "Post revision topic",
      body: "Original post body"
    ).value
    @post = @topic.posts.first
    SiteSetting.set("forum.edit_grace_period_minutes", "0")
  end

  test "two editors cannot overwrite the same expected revision" do
    first_copy = Community::Post.find(@post.id)
    stale_copy = Community::Post.find(@post.id)

    first = Community::EditPost.call(
      user: @author,
      post: first_copy,
      body: "First committed edit",
      expected_revision: 1
    )
    stale = Community::EditPost.call(
      user: @author,
      post: stale_copy,
      body: "Stale overwrite",
      expected_revision: 1
    )

    assert_predicate first, :success?, first.error
    assert_predicate stale, :failure?
    assert_equal "post_revision_conflict", stale.code
    assert_equal "First committed edit", @post.reload.body
    assert_equal 2, @post.revision
    assert_equal 1, @post.edits.count
  end

  test "invalid inline upload rolls back body revision and edit history" do
    result = Community::EditPost.call(
      user: @author,
      post: @post,
      body: "Changed body /forum/uploads/upl_#{SecureRandom.alphanumeric(24)}",
      expected_revision: 1
    )

    assert_predicate result, :failure?
    assert_equal "inline_upload_expired", result.code
    assert_equal "Original post body", @post.reload.body
    assert_equal 1, @post.revision
    assert_empty @post.edits
  end

  test "attachment authorization failure cannot leave a half-committed body" do
    attachment = Community::PostAttachment.create!(
      user: @other,
      filename: "not-owned.txt",
      content_type: "text/plain",
      byte_size: 4
    )

    result = Community::EditPost.call(
      user: @author,
      post: @post,
      body: "Body that must roll back",
      expected_revision: 1,
      attachment_ids: [ attachment.id ]
    )

    assert_predicate result, :failure?
    assert_equal "attachment_invalid_or_unauthorized", result.code
    assert_equal "Original post body", @post.reload.body
    assert_equal 1, @post.revision
    assert_empty @post.edits
    assert_nil attachment.reload.forum_post_id
  end

  test "stale controller response omits the success token so the draft stays open" do
    committed = Community::EditPost.call(
      user: @author,
      post: @post,
      body: "Newer server body",
      expected_revision: 1
    )
    assert_predicate committed, :success?, committed.error
    sign_in_as(@author)
    edit_token = "post-edit-#{SecureRandom.hex(8)}"

    patch forum_post_path(@post), params: {
      post: {
        body: "Stale browser draft",
        expected_revision: 1,
        edit_token: edit_token,
        attachment_ids: []
      }
    }

    assert_redirected_to forum_topic_path(@topic)
    follow_redirect!
    props = inertia.props.deep_symbolize_keys
    assert_nil props.dig(:flash, :post_edit_succeeded)
    assert_equal I18n.t("mcweb.services.errors.post_revision_conflict"), props.dig(:flash, :alert)
    assert_equal "Newer server body", @post.reload.body
  end
end

class EditPostPermissionMutationLockTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    suffix = SecureRandom.hex(6)
    @category = Community::Category.create!(name: "Permission edit #{suffix}", slug: "permission-edit-#{suffix}")
    @section = Community::Section.create!(
      category: @category,
      name: "Permission edit",
      slug: "permission-edit-#{suffix}",
      position: 0
    )
    @author = create_user(username: "perm_author_#{suffix}")
    @editor = create_user(username: "perm_staff_#{suffix}", account_type: "staff")
    @topic = Community::CreateTopic.call(
      user: @author,
      section: @section,
      title: "Permission edit topic",
      body: "Permission-sensitive original body"
    ).value
    @post = @topic.posts.first
    @permission = Permission.find_or_create_by!(key: "forum.posts.edit_others") do |permission|
      permission.name = "Edit other users' posts"
      permission.category = "forum"
    end
    @role = Role.create!(key: "permission_edit_#{suffix}", name: "Permission edit #{suffix}")
    @role.grant_permission!(@permission)
    UserRole.create!(user: @editor, role: @role)
    assert @editor.permission?(@permission.key), "the stale actor fixture must cache the granted permission"
  end

  teardown do
    @revoker&.join(5)
    Community::Topic.where(id: @topic&.id).destroy_all
    UserRole.where(role_id: @role&.id).delete_all
    RolePermission.where(role_id: @role&.id).delete_all
    Role.where(id: @role&.id).delete_all
    Community::Section.where(id: @section&.id).destroy_all
    Community::Category.where(id: @category&.id).destroy_all
    user_ids = [ @author&.id, @editor&.id ].compact
    AuditLog.where(actor_id: user_ids).delete_all
    User.where(id: user_ids).destroy_all
  end

  test "a committed revocation wins before the editor obtains the shared permission lock" do
    revocation_result = Queue.new
    editor_result = Queue.new

    @revoker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        ApplicationRecord.transaction do
          Identity::PermissionMutationLock.acquire_exclusive!
          RolePermission.where(role: @role, permission: @permission).destroy_all
        end
        revocation_result << true
      rescue StandardError => e
        revocation_result << e
      end
    end
    assert @revoker.join(5), "permission revocation did not commit"
    mutation = revocation_result.pop
    raise mutation if mutation.is_a?(Exception)
    assert @editor.permission?(@permission.key),
      "the original actor object must remain stale for this regression test"

    editor = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        editor_result << Community::EditPost.call(
          user: @editor,
          post: @post,
          body: "Revoked editor body",
          expected_revision: 1
        )
      rescue StandardError => e
        editor_result << e
      end
    end
    assert editor.join(5), "post edit did not resume after permission revocation"
    result = editor_result.pop
    raise result if result.is_a?(Exception)

    assert_predicate result, :failure?
    assert_equal "you_cannot_edit_this_post", result.code
    assert_equal "Permission-sensitive original body", @post.reload.body
    assert_equal 1, @post.revision
    assert_empty @post.edits
    assert_not User.find(@editor.id).permission?(@permission.key)
  ensure
    @revoker&.join(5)
    editor&.join(5)
  end
end
