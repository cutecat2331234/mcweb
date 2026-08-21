# frozen_string_literal: true

require Rails.root.join("lib/mcweb/migrations/community_message_revision_backfill")

module Mcweb
  module Migrations
    # Post-deploy gate for the cross-table revision contract. Run only after the
    # dual-writing application is healthy and every old web/worker process has
    # exited. The broad catch-up is lock-free; only the final bounded catch-up,
    # zero-row assertion, and deferred trigger installation hold the write lock.
    class CommunityMessageRevisionContract
      LOCK_TIMEOUT = "5s"

      def initialize(batch_size: CommunityMessageRevisionBackfill::BATCH_SIZE)
        @backfill = CommunityMessageRevisionBackfill.new(batch_size: batch_size)
        @connection = ActiveRecord::Base.connection
      end

      def call
        assert_dual_writer!
        preflight = @backfill.call
        final = nil

        ActiveRecord::Base.transaction(requires_new: true) do
          @connection.execute("SET LOCAL lock_timeout = #{@connection.quote(LOCK_TIMEOUT)}")
          @connection.execute("LOCK TABLE forum_messages IN SHARE ROW EXCLUSIVE MODE")
          final = @backfill.call
          assert_complete!(final)
          install_contract_trigger
        end

        {
          preflight_inserted: preflight.fetch(:inserted),
          final_inserted: final.fetch(:inserted),
          missing: final.fetch(:missing),
          queued: final.fetch(:queued),
          finalized: finalized?
        }
      end

      def finalized?
        trigger_present? && @backfill.missing_count.zero? && @backfill.queued_count.zero?
      end

      private

      def assert_dual_writer!
        callback_present = Community::Message._create_callbacks.any? do |callback|
          callback.kind == :after && callback.filter == :record_initial_revision
        end
        return if callback_present

        raise "Community::Message revision dual-write callback is not deployed"
      end

      def assert_complete!(result)
        return if result.fetch(:missing).zero? && result.fetch(:queued).zero?

        raise "message revision contract has missing or queued rows"
      end

      def trigger_present?
        ActiveModel::Type::Boolean.new.cast(
          @connection.select_value(<<~SQL.squish)
            SELECT EXISTS (
              SELECT 1
              FROM pg_trigger
              WHERE tgname = 'forum_messages_require_current_revision'
                AND tgrelid = 'forum_messages'::regclass
                AND NOT tgisinternal
            )
          SQL
        )
      end

      def install_contract_trigger
        @connection.execute <<~SQL
          CREATE OR REPLACE FUNCTION forum_messages_require_current_revision()
          RETURNS trigger
          LANGUAGE plpgsql
          AS $$
          BEGIN
            IF NOT EXISTS (
              SELECT 1
              FROM forum_message_revisions
              WHERE forum_message_id = NEW.id
                AND revision = NEW.revision
            ) THEN
              RAISE EXCEPTION 'forum message current revision is missing';
            END IF;
            RETURN NEW;
          END;
          $$;

          DROP TRIGGER IF EXISTS forum_messages_require_current_revision ON forum_messages;
          CREATE CONSTRAINT TRIGGER forum_messages_require_current_revision
          AFTER INSERT OR UPDATE OF revision ON forum_messages
          DEFERRABLE INITIALLY DEFERRED
          FOR EACH ROW
          EXECUTE FUNCTION forum_messages_require_current_revision();
        SQL
      end
    end
  end
end
