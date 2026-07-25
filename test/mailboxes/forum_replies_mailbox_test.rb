# frozen_string_literal: true

require "test_helper"
require "action_mailbox/test_helper"

class ForumRepliesMailboxTest < ActiveSupport::TestCase
  include ActionMailbox::TestHelper

  setup do
    @recipient = create_user(email: "reply-user-#{SecureRandom.hex(4)}@example.com")
    @author = create_user
    @category = Community::Category.create!(
      name: "Email reply category",
      slug: "email-reply-category-#{SecureRandom.hex(4)}"
    )
    @section = Community::Section.create!(
      category: @category,
      name: "Email reply section",
      slug: "email-reply-section-#{SecureRandom.hex(4)}",
      position: 0
    )
    @topic = create_topic(title: "Reply by email")
  end

  test "valid signed reply creates a post and removes quoted content" do
    reply_to = issue_address

    assert_difference -> { @topic.posts.count }, 1 do
      inbound = receive_reply(
        to: reply_to,
        from: "Reply User <#{@recipient.email}>",
        body: <<~BODY
          This is my email reply.

          On Fri, Jul 25, 2026 at 9:00 PM Author wrote:
          > This is the quoted notification.
        BODY
      )

      assert_predicate inbound.reload, :delivered?
    end

    delivery = Community::ForumEmailReplyDelivery.order(:created_at).last
    assert_equal "posted", delivery.status
    assert_equal @recipient, delivery.post.user
    assert_equal "This is my email reply.", delivery.post.body
    assert_equal @topic, delivery.post.topic
  end

  test "forged and expired reply addresses are rejected" do
    forged = "reply+#{'A' * 24}.#{'B' * 16}@example.com"

    forged_inbound = assert_no_difference -> { @topic.posts.count } do
      receive_reply(to: forged, from: @recipient.email, body: "Forged reply")
    end
    assert_predicate forged_inbound.reload, :bounced?
    assert_equal "invalid_reply_address",
      Community::ForumEmailReplyDelivery.find_by!(inbound_email: forged_inbound).rejection_reason

    expired = Community::ForumEmailReplyAddress.issue!(
      user: @recipient,
      topic: @topic,
      expires_in: -1.minute
    )
    expired_inbound = assert_no_difference -> { @topic.posts.count } do
      receive_reply(to: expired, from: @recipient.email, body: "Expired reply")
    end
    assert_predicate expired_inbound.reload, :bounced?
    assert_equal "expired_reply_address",
      Community::ForumEmailReplyDelivery.find_by!(inbound_email: expired_inbound).rejection_reason
  end

  test "the signed user binding is not replaced by a matching From display name" do
    reply_to = issue_address
    attacker = create_user

    inbound = assert_no_difference -> { @topic.posts.count } do
      receive_reply(
        to: reply_to,
        from: "#{@recipient.username} <#{attacker.email}>",
        body: "Attempted impersonation"
      )
    end

    assert_predicate inbound.reload, :bounced?
    assert_equal "sender_mismatch",
      Community::ForumEmailReplyDelivery.find_by!(inbound_email: inbound).rejection_reason
  end

  test "current section permissions and topic state are rechecked on receipt" do
    permission_address = issue_address
    @section.update!(permissions: { "reply" => [ "forum.email_reply.restricted" ] })

    permission_inbound = assert_no_difference -> { @topic.posts.count } do
      receive_reply(to: permission_address, from: @recipient.email, body: "No permission")
    end
    assert_predicate permission_inbound.reload, :bounced?
    assert_equal "reply_not_allowed",
      Community::ForumEmailReplyDelivery.find_by!(inbound_email: permission_inbound).rejection_reason

    @section.update!(permissions: {})
    closed_topic = create_topic(title: "Closed email reply topic")
    closed_address = Community::ForumEmailReplyAddress.issue!(user: @recipient, topic: closed_topic)
    closed_topic.update!(locked: true)

    closed_inbound = assert_no_difference -> { closed_topic.posts.count } do
      receive_reply(to: closed_address, from: @recipient.email, body: "Closed topic reply")
    end
    assert_predicate closed_inbound.reload, :bounced?
    assert_equal "topic_closed",
      Community::ForumEmailReplyDelivery.find_by!(inbound_email: closed_inbound).rejection_reason
  end

  test "account eligibility is rechecked on receipt" do
    reply_to = issue_address
    @recipient.update!(status: "deleted", deleted_at: Time.current)

    inbound = assert_no_difference -> { @topic.posts.count } do
      receive_reply(to: reply_to, from: @recipient.email, body: "Deleted account reply")
    end

    assert_predicate inbound.reload, :bounced?
    assert_equal "account_ineligible",
      Community::ForumEmailReplyDelivery.find_by!(inbound_email: inbound).rejection_reason
  end

  test "different inbound records with the same Message-ID are idempotent" do
    reply_to = issue_address
    message_id = "<forum-reply-#{SecureRandom.hex(8)}@example.com>"

    first = receive_reply(
      to: reply_to,
      from: @recipient.email,
      body: "Only post this once",
      message_id: message_id
    )
    first.route
    second = receive_reply(
      to: reply_to,
      from: @recipient.email,
      body: "Changed transport copy must not post",
      message_id: message_id
    )

    assert_predicate first.reload, :delivered?
    assert_predicate second.reload, :delivered?
    assert_equal 1, Community::ForumEmailReplyDelivery.where(
      message_id_digest: Digest::SHA256.hexdigest(message_id.delete_prefix("<").delete_suffix(">").downcase)
    ).count
    assert_equal 1, @topic.posts.where(user: @recipient).count
    assert_equal "Only post this once", @topic.posts.find_by!(user: @recipient).body
  end

  test "Message-ID evidence survives Action Mailbox raw-email incineration" do
    inbound = receive_reply(
      to: issue_address,
      from: @recipient.email,
      body: "Keep only the idempotency evidence"
    )
    delivery = Community::ForumEmailReplyDelivery.find_by!(inbound_email: inbound)

    assert_no_difference -> { Community::ForumEmailReplyDelivery.count } do
      inbound.destroy!
    end

    assert_nil delivery.reload.inbound_email
    assert_equal "posted", delivery.status
    assert_equal "Keep only the idempotency evidence", delivery.post.body
    assert_predicate delivery.message_id_digest, :present?
  end

  test "topic notification mail gets a short signed Reply-To address" do
    post = Community::Post.create!(
      topic: @topic,
      user: @author,
      floor_number: 2,
      body: "Notification reply",
      status: "published"
    )

    email = Community::ForumMailer.topic_reply(@recipient.id, @topic.public_id, post.id)
    reply_to = email.reply_to&.first

    assert_match(/\Areply\+[A-Za-z0-9_-]{24}\.[A-Za-z0-9_-]{16}@example\.com\z/, reply_to)
    token = Community::ForumEmailReplyAddress.token_from_recipient(reply_to)
    address = Community::ForumEmailReplyAddress.find_by_signed_token(token)
    assert_equal @recipient, address.user
    assert_equal @topic, address.topic
    assert_operator address.expires_at, :>, Time.current
  end

  test "plain text extraction removes Chinese quotes and mobile signatures" do
    quoted_mail = Mail.new do
      body <<~BODY
        这是新的邮件回复。

        在 2026 年 7 月 25 日，作者写道：
        > 这是旧内容。
      BODY
    end
    signed_mail = Mail.new do
      body <<~BODY
        这是手机发出的回复。

        从我的 iPhone 发送
        不应保留这一行。
      BODY
    end

    assert_equal "这是新的邮件回复。", Community::ExtractEmailReplyBody.call(quoted_mail)
    assert_equal "这是手机发出的回复。", Community::ExtractEmailReplyBody.call(signed_mail)
  end

  test "HTML extraction removes reply blockquotes" do
    html_mail = Mail.new
    html_mail.html_part = Mail::Part.new do
      content_type "text/html; charset=UTF-8"
      body <<~HTML
        <p>Hello <strong>from email</strong>.</p>
        <p>Second line.</p>
        <blockquote>Old quoted post.</blockquote>
      HTML
    end

    assert_equal "Hello from email.\n\nSecond line.", Community::ExtractEmailReplyBody.call(html_mail)
  end

  private

  def create_topic(title:)
    topic = Community::Topic.create!(
      section: @section,
      user: @author,
      title: title,
      status: "published",
      last_posted_at: 1.hour.ago,
      last_post_user: @author,
      replies_count: 0
    )
    Community::Post.create!(
      topic: topic,
      user: @author,
      floor_number: 1,
      body: "Initial topic post",
      status: "published",
      created_at: 1.hour.ago
    )
    topic
  end

  def issue_address
    Community::ForumEmailReplyAddress.issue!(user: @recipient, topic: @topic)
  end

  def receive_reply(to:, from:, body:, message_id: nil)
    receive_inbound_email_from_mail(
      to: to,
      from: from,
      subject: "Re: #{@topic.title}",
      body: body,
      message_id: message_id || "<forum-reply-#{SecureRandom.hex(8)}@example.com>"
    )
  end
end
