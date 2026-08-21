# frozen_string_literal: true

module Community
  class BuildReportEvidence < ApplicationService
    def initialize(reportable:)
      @reportable = reportable
    end

    def call
      snapshot, revision = snapshot_and_revision
      return ServiceResult.failure(error: "report_target_unavailable") unless snapshot

      ServiceResult.success(
        snapshot: snapshot,
        subject_type: @reportable.class.name,
        subject_id: @reportable.id,
        subject_revision: revision,
        content_digest: Digest::SHA256.hexdigest(JSON.generate(snapshot)),
        captured_at: Time.current
      )
    end

    private

    def snapshot_and_revision
      case @reportable
      when Community::Message
        [ message_snapshot(@reportable), @reportable.revision ]
      when Community::Post
        [ post_snapshot(@reportable), @reportable.edits.count + 1 ]
      when Community::Topic
        [ topic_snapshot(@reportable), 1 ]
      when Community::ProfilePost
        [ profile_post_snapshot(@reportable), @reportable.revision ]
      when Community::ProfilePostComment
        [ profile_comment_snapshot(@reportable), @reportable.revision ]
      when Commerce::Review
        [ review_snapshot(@reportable), 1 ]
      when User
        [ user_snapshot(@reportable), 1 ]
      end
    end

    def message_snapshot(message)
      {
        "body" => message.body,
        "conversation_id" => message.forum_conversation_id,
        "created_at" => message.created_at.iso8601(6),
        "edited_at" => message.edited_at&.iso8601(6),
        "sender_id" => message.user_id
      }
    end

    def post_snapshot(post)
      {
        "author_id" => post.user_id,
        "body" => post.body,
        "created_at" => post.created_at.iso8601(6),
        "edited_at" => post.edited_at&.iso8601(6),
        "floor_number" => post.floor_number,
        "status" => post.status,
        "topic_id" => post.forum_topic_id
      }
    end

    def topic_snapshot(topic)
      first_post = topic.posts.order(:floor_number).lock.first
      {
        "author_id" => topic.user_id,
        "body" => first_post&.body,
        "created_at" => topic.created_at.iso8601(6),
        "status" => topic.status,
        "title" => topic.title
      }
    end

    def profile_post_snapshot(post)
      {
        "author_id" => post.user_id,
        "body" => post.body,
        "created_at" => post.created_at.iso8601(6),
        "edited_at" => post.edited_at&.iso8601(6),
        "profile_user_id" => post.profile_user_id,
        "status" => post.status
      }
    end

    def profile_comment_snapshot(comment)
      {
        "author_id" => comment.user_id,
        "body" => comment.body,
        "created_at" => comment.created_at.iso8601(6),
        "edited_at" => comment.edited_at&.iso8601(6),
        "profile_post_id" => comment.profile_post_id,
        "status" => comment.status
      }
    end

    def review_snapshot(review)
      {
        "author_id" => review.user_id,
        "body" => review.body,
        "created_at" => review.created_at.iso8601(6),
        "product_id" => review.store_product_id,
        "rating" => review.rating,
        "status" => review.status
      }
    end

    def user_snapshot(user)
      {
        "bio" => user.bio,
        "status" => user.status,
        "username" => user.username
      }
    end
  end
end
