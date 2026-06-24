# frozen_string_literal: true

require "test_helper"

class EditPostGraceWindowTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.create!(name: "C", slug: "c-#{SecureRandom.hex(3)}")
    @section = Community::Section.create!(category: category, name: "S", slug: "s-#{SecureRandom.hex(3)}", position: 0)
    @topic = Community::Topic.create!(
      public_id: "t_#{SecureRandom.alphanumeric(10)}",
      section: @section, user: @user, title: "T", status: "published",
      last_posted_at: Time.current, last_post_user: @user, replies_count: 0
    )
    @post = Community::Post.create!(topic: @topic, user: @user, floor_number: 1, body: "original body content", status: "published")
    SiteSetting.set("forum.edit_grace_period_minutes", "5")
  end

  test "quick self-edit within the grace window leaves no revision or edited marker" do
    assert_no_difference -> { @post.edits.count } do
      result = Community::EditPost.call(user: @user, post: @post, body: "fixed a quick typo in the body")
      assert result.success?, result.error
    end
    assert_nil @post.reload.edited_at
    assert_equal "fixed a quick typo in the body", @post.body
  end

  test "edit after the grace window records a revision and edited_at" do
    @post.update_column(:created_at, 10.minutes.ago)
    assert_difference -> { @post.edits.count }, 1 do
      result = Community::EditPost.call(user: @user, post: @post, body: "a later substantive edit to the body")
      assert result.success?, result.error
    end
    assert_not_nil @post.reload.edited_at
  end
end
