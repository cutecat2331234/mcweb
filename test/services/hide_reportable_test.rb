# frozen_string_literal: true

require "test_helper"

class HideReportableTest < ActiveSupport::TestCase
  setup do
    @author = create_user
    category = Community::Category.create!(name: "C", slug: "c-#{SecureRandom.hex(3)}")
    section = Community::Section.create!(category: category, name: "S", slug: "s-#{SecureRandom.hex(3)}", position: 0)
    @topic = Community::Topic.create!(
      public_id: "t_#{SecureRandom.alphanumeric(10)}",
      section: section, user: @author, title: "T", status: "published",
      last_posted_at: Time.current, last_post_user: @author, replies_count: 0
    )
    @post = Community::Post.create!(topic: @topic, user: @author, floor_number: 1, body: "body", status: "published")
  end

  test "hides a reported post" do
    result = Community::HideReportable.call(reportable: @post)
    assert result.success?
    assert_equal "hidden", @post.reload.status
  end

  test "hides a reported topic" do
    result = Community::HideReportable.call(reportable: @topic)
    assert result.success?
    assert_equal "hidden", @topic.reload.status
  end

  test "does not hide a soft-deleted post" do
    @post.update_columns(deleted_at: Time.current)
    assert Community::HideReportable.call(reportable: @post).success?
    assert_equal "published", Community::Post.unscoped.find(@post.id).status
  end

  test "is a safe no-op for a nil reportable" do
    result = Community::HideReportable.call(reportable: nil)
    assert_predicate result, :success?
    assert_equal false, result.value.fetch(:hidden)
  end

  test "private messages are retained and never reported as hidden" do
    recipient = create_user
    conversation = Community::Conversation.create!
    conversation.participants.create!(user: @author)
    conversation.participants.create!(user: recipient)
    message = conversation.messages.create!(user: @author, body: "Retained private message")

    result = Community::HideReportable.call(reportable: message)

    assert_predicate result, :success?
    assert_equal false, result.value.fetch(:hidden)
    assert_equal "unsupported_or_retained_reportable", result.value.fetch(:skipped)
    assert Community::Message.exists?(message.id)
    assert_equal "Retained private message", message.reload.body
  end
end
