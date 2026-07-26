# frozen_string_literal: true

require "test_helper"

class Community::PostAttachmentAtomicityTest < ActiveSupport::TestCase
  setup do
    suffix = SecureRandom.hex(5)
    category = Community::Category.create!(
      name: "Attachment atomicity #{suffix}",
      slug: "attachment-atomicity-#{suffix}"
    )
    @section = Community::Section.create!(
      category: category,
      name: "Attachment atomicity",
      slug: "attachment-atomicity-#{suffix}",
      position: 0
    )
    @author = create_user(
      username: "attachment_author_#{suffix}",
      forum_trust_level_override: 1
    )
    @other = create_user(
      username: "attachment_other_#{suffix}",
      forum_trust_level_override: 1
    )
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @author,
      title: "Existing attachment topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @author,
      replies_count: 0
    )
    Community::Post.create!(
      topic: @topic,
      user: @author,
      floor_number: 1,
      body: "Opening post",
      status: "published"
    )
    SiteSetting.set("forum.event_webhook_url", "https://example.com/forum-events")
    SiteSetting.set("forum.event_webhook_events", "topic.created,post.created")
  end

  test "topic creation rejects a partially unauthorized attachment set before content or side effects" do
    owned_attachment = create_attachment(user: @author, filename: "owned-topic.txt")
    unauthorized_attachment = create_attachment(user: @other, filename: "other-topic.txt")

    assert_no_content_or_side_effect_changes do
      result = Community::CreateTopic.call(
        user: @author,
        section: @section,
        title: "Atomic topic #{SecureRandom.hex(3)}",
        body: "This topic must not be persisted.",
        attachment_ids: [ owned_attachment.id, unauthorized_attachment.id ]
      )

      assert_predicate result, :failure?
    end

    assert_nil owned_attachment.reload.forum_post_id
    assert_nil unauthorized_attachment.reload.forum_post_id
  end

  test "reply creation rejects a partially unauthorized attachment set before content or side effects" do
    owned_attachment = create_attachment(user: @author, filename: "owned-reply.txt")
    unauthorized_attachment = create_attachment(user: @other, filename: "other-reply.txt")

    assert_no_content_or_side_effect_changes do
      result = Community::CreatePost.call(
        user: @author,
        topic: @topic,
        body: "This reply must not be persisted.",
        attachment_ids: [ owned_attachment.id, unauthorized_attachment.id ],
        skip_interval_check: true
      )

      assert_predicate result, :failure?
    end

    assert_nil owned_attachment.reload.forum_post_id
    assert_nil unauthorized_attachment.reload.forum_post_id
  end

  test "topic and attachment rows roll back together when binding fails after content creation" do
    attachment = create_attachment(user: @author, filename: "rollback-topic.txt")
    failure = ServiceResult.failure(error: "attachment_invalid_or_unauthorized")

    assert_no_content_or_side_effect_changes do
      with_stubbed_call(Community::LinkPostAttachments, ->(**) { failure }) do
        result = Community::CreateTopic.call(
          user: @author,
          section: @section,
          title: "Rollback topic #{SecureRandom.hex(3)}",
          body: "The transaction must roll back.",
          attachment_ids: [ attachment.id ]
        )

        assert_predicate result, :failure?
      end
    end

    assert_nil attachment.reload.forum_post_id
  end

  test "reply and attachment rows roll back together when binding fails after content creation" do
    attachment = create_attachment(user: @author, filename: "rollback-reply.txt")
    failure = ServiceResult.failure(error: "attachment_invalid_or_unauthorized")

    assert_no_content_or_side_effect_changes do
      with_stubbed_call(Community::LinkPostAttachments, ->(**) { failure }) do
        result = Community::CreatePost.call(
          user: @author,
          topic: @topic,
          body: "The reply transaction must roll back.",
          attachment_ids: [ attachment.id ],
          skip_interval_check: true
        )

        assert_predicate result, :failure?
      end
    end

    assert_nil attachment.reload.forum_post_id
  end

  test "an attachment validation rollback does not roll back the reply abuse counter" do
    SiteSetting.set("security.rate_limits.reply.account_limit", "1")
    SiteSetting.set("security.rate_limits.reply.ip_limit", "100")
    unauthorized_attachment = create_attachment(user: @other, filename: "rate-limit.txt")

    rejected = Community::CreatePost.call(
      user: @author,
      topic: @topic,
      body: "Rejected attachment attempt.",
      attachment_ids: [ unauthorized_attachment.id ],
      ip_address: "192.0.2.44",
      skip_interval_check: true
    )
    assert_predicate rejected, :failure?

    retry_result = Community::CreatePost.call(
      user: @author,
      topic: @topic,
      body: "A second attempt after rollback.",
      ip_address: "192.0.2.44",
      skip_interval_check: true
    )

    assert_predicate retry_result, :rate_limited?
    assert_operator retry_result.retry_after, :>, 0
  end

  private

  def create_attachment(user:, filename:)
    attachment = Community::PostAttachment.create!(
      user: user,
      filename: filename,
      content_type: "text/plain",
      byte_size: 4
    )
    attachment.file.attach(
      io: StringIO.new("data"),
      filename: filename,
      content_type: "text/plain"
    )
    attachment
  end

  def assert_no_content_or_side_effect_changes(&block)
    assert_no_enqueued_jobs do
      assert_no_difference -> { Community::Topic.count } do
        assert_no_difference -> { Community::Post.count } do
          assert_no_difference -> { Community::Subscription.count } do
            assert_no_difference -> { Community::ReadState.count } do
              assert_no_difference -> { AuditLog.count } do
                assert_no_difference -> { Notification.count }, &block
              end
            end
          end
        end
      end
    end
  end

  def with_stubbed_call(klass, replacement)
    singleton = klass.singleton_class
    had_own_call = singleton.instance_methods(false).include?(:call)
    original = klass.method(:call)
    singleton.define_method(:call) { |**kwargs| replacement.call(**kwargs) }
    yield
  ensure
    if had_own_call
      singleton.define_method(:call, original)
    elsif singleton.instance_methods(false).include?(:call)
      singleton.send(:remove_method, :call)
    end
  end
end
