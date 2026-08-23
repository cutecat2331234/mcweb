# frozen_string_literal: true

module Identity
  module DataExporting
    class CommunityActivityContributor
      BOOKMARK_FIELDS = %w[
        id forum_topic_id forum_post_id label note remind_at created_at updated_at
      ].freeze
      REACTION_FIELDS = %w[id forum_post_id emoji created_at updated_at].freeze
      SAVED_SEARCH_FIELDS = %w[
        id name query filters notify_daily notify_in_app webhook_url last_notified_at
        created_at updated_at
      ].freeze
      PROFILE_POST_FIELDS = %w[
        id profile_user_id body status revision edited_at deleted_at created_at updated_at
      ].freeze
      PROFILE_COMMENT_FIELDS = %w[
        id profile_post_id body status revision edited_at deleted_at created_at updated_at
      ].freeze
      POINT_ACCOUNT_FIELDS = %w[id currency balance created_at updated_at].freeze
      POINT_TRANSACTION_FIELDS = %w[
        id forum_point_account_id currency amount balance_after reason source_type source_id
        created_at updated_at
      ].freeze

      def self.call(context:)
        user = context.user
        Contribution.new(
          documents: {
            "forum/bookmarks.json" => RecordSerializer.records(
              Community::Bookmark.where(user:).order(:id),
              BOOKMARK_FIELDS
            ),
            "forum/relationships/follows.json" => relationships(
              Community::UserFollow.where(follower: user).includes(:followed).order(:id),
              :followed
            ),
            "forum/relationships/blocks.json" => relationships(
              Community::UserBlock.where(blocker: user).includes(:blocked).order(:id),
              :blocked
            ),
            "forum/relationships/ignores.json" => relationships(
              Community::UserIgnore.where(ignorer: user).includes(:ignored).order(:id),
              :ignored
            ),
            "forum/reactions.json" => RecordSerializer.records(
              Community::Reaction.where(user:).order(:id),
              REACTION_FIELDS
            ),
            "forum/saved-searches.json" => RecordSerializer.records(
              Community::SavedSearch.where(user:).order(:id),
              SAVED_SEARCH_FIELDS
            ),
            "forum/profile-posts.json" => RecordSerializer.records(
              Community::ProfilePost.with_discarded.where(user_id: user.id).order(:id),
              PROFILE_POST_FIELDS
            ),
            "forum/profile-post-comments.json" => RecordSerializer.records(
              Community::ProfilePostComment.with_discarded.where(user_id: user.id).order(:id),
              PROFILE_COMMENT_FIELDS
            ),
            "forum/points/accounts.json" => RecordSerializer.records(
              Community::PointAccount.where(user:).order(:id),
              POINT_ACCOUNT_FIELDS
            ),
            "forum/points/transactions.json" => RecordSerializer.records(
              Community::PointTransaction.where(user:).order(:id),
              POINT_TRANSACTION_FIELDS
            )
          }
        )
      end

      def self.relationships(scope, association)
        scope.map do |relationship|
          target = relationship.public_send(association)
          {
            "id" => relationship.id,
            "target_public_id" => target.public_id,
            "target_username" => target.username,
            "created_at" => relationship.created_at,
            "updated_at" => relationship.updated_at
          }
        end
      end
      private_class_method :relationships
    end
  end
end
