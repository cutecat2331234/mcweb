# frozen_string_literal: true

module Community
  class ContentRequest < ApplicationRecord
    self.table_name = "forum_content_requests"

    OPERATIONS = %w[topic.create post.create].freeze

    belongs_to :user
    belongs_to :topic,
      class_name: "Community::Topic",
      foreign_key: :forum_topic_id,
      optional: true
    belongs_to :post,
      class_name: "Community::Post",
      foreign_key: :forum_post_id,
      optional: true

    validates :operation, inclusion: { in: OPERATIONS }
    validates :key_digest, :request_fingerprint,
      presence: true,
      format: { with: /\A\h{64}\z/ }

    def resource
      operation == "topic.create" ? topic : post
    end

    def complete!(record)
      case operation
      when "topic.create"
        raise ArgumentError, "Expected a forum topic." unless record.is_a?(Community::Topic)

        update!(topic: record)
      when "post.create"
        raise ArgumentError, "Expected a forum post." unless record.is_a?(Community::Post)

        update!(post: record)
      else
        raise ArgumentError, "Unknown content request operation."
      end
    end
  end
end
