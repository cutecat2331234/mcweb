# frozen_string_literal: true

module Mcweb
  module Migrations
    # Restartable, bounded backfill used both by the data migration and by the
    # explicit post-deploy contract gate. Each insert batch commits separately
    # unless the caller deliberately wraps the final, small catch-up in a lock.
    class CommunityMessageRevisionBackfill
      BATCH_SIZE = 250
      UNIQUE_INDEX = "idx_forum_message_revisions_unique"
      MISSING_CURRENT_REVISION = <<~SQL.squish.freeze
        NOT EXISTS (
          SELECT 1
          FROM forum_message_revisions AS revisions
          WHERE revisions.forum_message_id = forum_messages.id
            AND revisions.revision = forum_messages.revision
        )
      SQL

      class Message < ActiveRecord::Base
        self.table_name = "forum_messages"
      end

      class Revision < ActiveRecord::Base
        self.table_name = "forum_message_revisions"

        has_encrypted :body, encrypted_attribute: :encrypted_body
      end

      class QueueEntry < ActiveRecord::Base
        self.table_name = "forum_message_revision_backfill_queue"
        self.primary_key = :forum_message_id
      end

      def initialize(batch_size: BATCH_SIZE)
        @batch_size = Integer(batch_size)
        raise ArgumentError, "batch_size must be positive" unless @batch_size.positive?
      end

      def call
        reset_models!
        inserted = 0
        # Bound this run so sustained old-process traffic cannot make a deploy
        # migration chase a moving tail forever. Inserts above this watermark
        # stay in the database-backed queue for the post-deploy catch-up.
        upper_bound_id = Message.maximum(:id)

        if upper_bound_id
          loop do
            messages = missing_scope.where(id: ..upper_bound_id).order(:id).limit(@batch_size).to_a
            break if messages.empty?

            result = Revision.insert_all(
              messages.map { |message| revision_attributes(message) },
              unique_by: UNIQUE_INDEX,
              returning: %w[id]
            )
            inserted += result.rows.length
          end
        end

        clear_satisfied_queue!
        {
          inserted: inserted,
          missing: missing_count,
          queued: queued_count
        }
      end

      def missing_count
        reset_models!
        missing_scope.unscope(:select).count
      end

      def queued_count
        reset_models!
        QueueEntry.count
      end

      private

      def missing_scope
        Message
          .select(:id, :user_id, :revision, :body, :created_at)
          .where(MISSING_CURRENT_REVISION)
      end

      def revision_attributes(message)
        revision = Revision.new
        revision.body = message.body.to_s
        unless revision.encrypted_body.present? && revision.body == message.body
          raise "forum message revision encryption failed for row #{message.id}"
        end

        {
          forum_message_id: message.id,
          editor_id: message.user_id,
          revision: message.revision,
          encrypted_body: revision.encrypted_body,
          content_digest: Digest::SHA256.hexdigest(message.body.to_s),
          created_at: message.created_at || Time.current
        }
      end

      def clear_satisfied_queue!
        loop do
          message_ids = QueueEntry
            .where(<<~SQL.squish)
              EXISTS (
                SELECT 1
                FROM forum_messages AS messages
                INNER JOIN forum_message_revisions AS revisions
                  ON revisions.forum_message_id = messages.id
                 AND revisions.revision = messages.revision
                WHERE messages.id = forum_message_revision_backfill_queue.forum_message_id
              )
            SQL
            .limit(@batch_size)
            .pluck(:forum_message_id)
          break if message_ids.empty?

          QueueEntry.where(forum_message_id: message_ids).delete_all
        end
      end

      def reset_models!
        Message.reset_column_information
        Revision.reset_column_information
        QueueEntry.reset_column_information
      end
    end
  end
end
