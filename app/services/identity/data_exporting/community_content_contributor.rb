# frozen_string_literal: true

module Identity
  module DataExporting
    class CommunityContentContributor
      TOPIC_FIELDS = %w[public_id title status created_at updated_at deleted_at forum_section_id].freeze
      POST_FIELDS = %w[id forum_topic_id body status post_type created_at updated_at deleted_at edited_at].freeze
      MESSAGE_FIELDS = %w[id forum_conversation_id body created_at updated_at edited_at deleted_at].freeze

      def self.call(context:)
        user = context.user
        Contribution.new(
          documents: {
            "forum/topics.json" => RecordSerializer.records(
              Community::Topic.where(user:).order(:id),
              TOPIC_FIELDS
            ),
            "forum/posts.json" => RecordSerializer.records(
              Community::Post.where(user:).order(:id),
              POST_FIELDS
            ),
            "forum/messages.json" => RecordSerializer.records(
              Community::Message.where(user:).order(:id),
              MESSAGE_FIELDS
            )
          }
        )
      end
    end
  end
end
