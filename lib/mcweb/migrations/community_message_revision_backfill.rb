# frozen_string_literal: true

module Mcweb
  module Migrations
    # Restartable, bounded encrypted-snapshot backfill. A full run is capped at
    # its starting message ID watermark. The post-deploy gate uses call_queue so
    # the write-lock window touches only a hard-bounded, trigger-captured tail.
    class CommunityMessageRevisionBackfill
      BATCH_SIZE = 250
      UNIQUE_INDEX = "idx_forum_message_revisions_unique"
      BODY_DIGEST_SQL = <<~SQL.squish.freeze
        encode(digest(convert_to(forum_messages.body, 'UTF8'), 'sha256'), 'hex')
      SQL
      MISSING_REVISION = <<~SQL.squish.freeze
        NOT EXISTS (
          SELECT 1
          FROM forum_message_revisions AS revisions
          WHERE revisions.forum_message_id = forum_messages.id
            AND revisions.revision = forum_messages.revision
        )
      SQL
      UNRESOLVED_CURRENT_SNAPSHOT = <<~SQL.squish.freeze
        NOT EXISTS (
          SELECT 1
          FROM forum_message_revisions AS revisions
          WHERE revisions.forum_message_id = forum_messages.id
            AND revisions.revision = forum_messages.revision
            AND revisions.content_digest = #{BODY_DIGEST_SQL}
        )
      SQL

      class TailLimitExceeded < StandardError
        attr_reader :limit

        def initialize(limit)
          @limit = limit
          super("message revision tail exceeds the bounded limit of #{limit}")
        end
      end

      class Message < ActiveRecord::Base
        self.table_name = "forum_messages"
      end

      class Revision < ActiveRecord::Base
        self.table_name = "forum_message_revisions"

        has_encrypted :body, encrypted_attribute: :encrypted_body
      end

      class QueueEntry < ActiveRecord::Base
        self.table_name = "forum_message_revision_backfill_queue"
        self.primary_key = nil
      end

      def initialize(batch_size: BATCH_SIZE)
        @batch_size = Integer(batch_size)
        raise ArgumentError, "batch_size must be positive" unless @batch_size.positive?
      end

      def call(up_to: nil)
        reset_models!
        watermark = up_to || Message.maximum(:id)
        inserted = watermark ? backfill_missing_revisions(up_to: watermark) : 0
        enqueue_unresolved!(up_to: watermark) if watermark
        clear_satisfied_queue!

        {
          inserted: inserted,
          missing: missing_count,
          missing_through_watermark: watermark ? missing_count(up_to: watermark) : 0,
          queued: queued_count,
          watermark: watermark
        }
      end

      # Must be called while writes to forum_messages are blocked. It never scans
      # the message table: every candidate comes from the reliable database queue.
      def call_queue(limit:)
        reset_models!
        limit = Integer(limit)
        raise ArgumentError, "limit must be positive" unless limit.positive?

        entries = QueueEntry.order(:queued_at, :forum_message_id, :revision).limit(limit + 1).to_a
        raise TailLimitExceeded, limit if entries.length > limit

        messages = Message.where(id: entries.map(&:forum_message_id)).index_by(&:id)
        attributes = entries.filter_map do |entry|
          message = messages[entry.forum_message_id]
          next unless message
          next unless message.revision == entry.revision
          next unless content_digest(message.body) == entry.body_digest
          next if Revision.exists?(forum_message_id: message.id, revision: message.revision)

          revision_attributes(message)
        end
        inserted = insert_revisions(attributes)
        clear_satisfied_queue!

        remaining = QueueEntry.limit(1).exists?
        {
          inserted: inserted,
          remaining: remaining,
          queued: remaining ? 1 : 0
        }
      end

      def missing_count(up_to: nil)
        reset_models!
        scope = unresolved_scope
        scope = scope.where(id: ..up_to) if up_to
        scope.unscope(:select).count
      end

      def queued_count
        reset_models!
        QueueEntry.count
      end

      private

      def backfill_missing_revisions(up_to:)
        inserted = 0
        loop do
          messages = missing_revision_scope
            .where(id: ..up_to)
            .order(:id)
            .limit(@batch_size)
            .to_a
          break if messages.empty?

          inserted += insert_revisions(messages.map { |message| revision_attributes(message) })
        end
        inserted
      end

      def insert_revisions(attributes)
        return 0 if attributes.empty?

        attributes.each_slice(@batch_size).sum do |batch|
          result = Revision.insert_all(
            batch,
            unique_by: UNIQUE_INDEX,
            returning: %w[id]
          )
          result.rows.length
        end
      end

      def missing_revision_scope
        Message
          .select(:id, :user_id, :revision, :body, :created_at)
          .where(MISSING_REVISION)
      end

      def unresolved_scope
        Message
          .select(:id)
          .where(UNRESOLVED_CURRENT_SNAPSHOT)
      end

      def enqueue_unresolved!(up_to:)
        connection.execute <<~SQL.squish
          INSERT INTO forum_message_revision_backfill_queue (
            forum_message_id,
            revision,
            body_digest,
            queued_at
          )
          SELECT
            forum_messages.id,
            forum_messages.revision,
            #{BODY_DIGEST_SQL},
            CURRENT_TIMESTAMP
          FROM forum_messages
          WHERE forum_messages.id <= #{Integer(up_to)}
            AND #{UNRESOLVED_CURRENT_SNAPSHOT}
          ON CONFLICT (forum_message_id, revision) DO NOTHING
        SQL
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
          content_digest: content_digest(message.body),
          created_at: message.created_at || Time.current
        }
      end

      def clear_satisfied_queue!
        connection.execute <<~SQL.squish
          DELETE FROM forum_message_revision_backfill_queue AS queue
          WHERE EXISTS (
            SELECT 1
            FROM forum_message_revisions AS revisions
            WHERE revisions.forum_message_id = queue.forum_message_id
              AND revisions.revision = queue.revision
              AND revisions.content_digest = queue.body_digest
          )
        SQL
      end

      def content_digest(body)
        Digest::SHA256.hexdigest(body.to_s)
      end

      def connection
        ActiveRecord::Base.connection
      end

      def reset_models!
        Message.reset_column_information
        Revision.reset_column_information
        QueueEntry.reset_column_information
      end
    end
  end
end
