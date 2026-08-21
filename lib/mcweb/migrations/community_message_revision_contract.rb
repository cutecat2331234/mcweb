# frozen_string_literal: true

require Rails.root.join("lib/mcweb/migrations/community_message_revision_backfill")

module Mcweb
  module Migrations
    # Post-deploy gate for the cross-table revision contract. Run only after the
    # dual-writing application is healthy and every old web/worker process has
    # exited. Full scans occur before the write lock. The locked phase handles
    # only the database-triggered tail, subject to a hard row limit.
    class CommunityMessageRevisionContract
      LOCK_TIMEOUT = "5s"
      STATEMENT_TIMEOUT = "30s"
      TAIL_LIMIT = 1_000

      def initialize(
        batch_size: CommunityMessageRevisionBackfill::BATCH_SIZE,
        tail_limit: TAIL_LIMIT,
        lock_timeout: LOCK_TIMEOUT,
        statement_timeout: STATEMENT_TIMEOUT
      )
        @backfill = CommunityMessageRevisionBackfill.new(batch_size: batch_size)
        @tail_limit = Integer(tail_limit)
        raise ArgumentError, "tail_limit must be positive" unless @tail_limit.positive?

        @lock_timeout = lock_timeout.to_s
        @statement_timeout = statement_timeout.to_s
        @connection = ActiveRecord::Base.connection
      end

      def call
        assert_dual_writer!

        with_statement_timeout do
          assert_revision_capture_protocol!
          preflight = @backfill.call
          tail = nil
          before_write_lock(preflight)

          ActiveRecord::Base.transaction(requires_new: true) do
            @connection.execute("SET LOCAL lock_timeout = #{@connection.quote(@lock_timeout)}")
            @connection.execute("SET LOCAL statement_timeout = #{@connection.quote(@statement_timeout)}")
            @connection.execute("LOCK TABLE forum_messages IN SHARE ROW EXCLUSIVE MODE")
            assert_revision_capture_protocol!
            tail = @backfill.call_queue(limit: @tail_limit)
            assert_tail_complete!(tail)
            install_contract_trigger
          end

          {
            preflight_inserted: preflight.fetch(:inserted),
            watermark: preflight.fetch(:watermark),
            tail_inserted: tail.fetch(:inserted),
            finalized: finalized?
          }
        end
      end

      # This status scan is deliberately outside the write-lock window.
      def finalized?
        with_statement_timeout do
          trigger_present? && @backfill.queued_count.zero? && @backfill.missing_count.zero?
        end
      end

      private

      def assert_dual_writer!
        callback_present = Community::Message._create_callbacks.any? do |callback|
          callback.kind == :after && callback.filter == :record_initial_revision
        end
        return if callback_present

        raise "Community::Message revision dual-write callback is not deployed"
      end

      # Test seam for proving that writes committed after the high-watermark
      # scan are captured by the database queue. Production execution is a no-op.
      def before_write_lock(_preflight)
      end

      def assert_tail_complete!(result)
        return unless result.fetch(:remaining)

        raise "message revision contract has an unresolved trigger-captured tail"
      end

      def assert_revision_capture_protocol!
        expected = {
          "forum_messages_prepare_revision_update" => {
            type: 19,
            columns: %w[body revision],
            function: "forum_messages_prepare_revision_update",
            function_markers: [
              "forum_message_revision_backfill_queue",
              "NEW.revision := OLD.revision + 1"
            ]
          },
          "forum_messages_queue_revision_backfill" => {
            type: 21,
            columns: %w[body revision],
            function: "forum_messages_queue_revision_backfill",
            function_markers: [
              "digest(convert_to(NEW.body, 'UTF8'), 'sha256')",
              "ON CONFLICT (forum_message_id, revision) DO NOTHING"
            ]
          },
          "forum_message_revisions_dequeue_backfill" => {
            type: 5,
            columns: [],
            function: "forum_message_revisions_dequeue_backfill",
            function_markers: [
              "revision = NEW.revision",
              "body_digest = NEW.content_digest"
            ]
          }
        }
        rows = @connection.select_all(<<~SQL.squish).index_by { |row| row.fetch("trigger_name") }
          SELECT
            triggers.tgname AS trigger_name,
            triggers.tgenabled,
            triggers.tgtype,
            procedures.proname AS function_name,
            procedure_namespaces.nspname AS function_schema,
            current_schema() AS current_schema,
            pg_get_functiondef(procedures.oid) AS function_definition,
            (
              SELECT string_agg(attributes.attname, ',' ORDER BY selected.ordinality)
              FROM unnest(triggers.tgattr::smallint[]) WITH ORDINALITY AS selected(attnum, ordinality)
              INNER JOIN pg_attribute AS attributes
                ON attributes.attrelid = triggers.tgrelid
               AND attributes.attnum = selected.attnum
            ) AS update_columns
          FROM pg_trigger AS triggers
          INNER JOIN pg_class AS tables
            ON tables.oid = triggers.tgrelid
          INNER JOIN pg_namespace AS table_namespaces
            ON table_namespaces.oid = tables.relnamespace
          INNER JOIN pg_proc AS procedures
            ON procedures.oid = triggers.tgfoid
          INNER JOIN pg_namespace AS procedure_namespaces
            ON procedure_namespaces.oid = procedures.pronamespace
          WHERE table_namespaces.nspname = current_schema()
            AND tables.relname IN ('forum_messages', 'forum_message_revisions')
            AND triggers.tgname IN (
              'forum_messages_prepare_revision_update',
              'forum_messages_queue_revision_backfill',
              'forum_message_revisions_dequeue_backfill'
            )
            AND NOT triggers.tgisinternal
        SQL

        valid = expected.all? do |trigger_name, contract|
          row = rows[trigger_name]
          next false unless row

          columns = row.fetch("update_columns").to_s.split(",").reject(&:empty?).sort
          row.fetch("tgenabled") == "O" &&
            row.fetch("tgtype").to_i == contract.fetch(:type) &&
            columns == contract.fetch(:columns).sort &&
            row.fetch("function_name") == contract.fetch(:function) &&
            row.fetch("function_schema") == row.fetch("current_schema") &&
            contract.fetch(:function_markers).all? do |marker|
              row.fetch("function_definition").include?(marker)
            end
        end
        return if valid

        raise "forum message revision capture protocol is missing or altered"
      end

      def trigger_present?
        row = @connection.select_one(<<~SQL.squish)
          SELECT
            triggers.tgenabled,
            triggers.tgtype,
            triggers.tgdeferrable,
            triggers.tginitdeferred,
            (triggers.tgconstraint <> 0) AS constraint_trigger,
            procedures.proname AS function_name,
            procedure_namespaces.nspname AS function_schema,
            current_schema() AS current_schema,
            pg_get_functiondef(procedures.oid) AS function_definition,
            pg_get_triggerdef(triggers.oid, TRUE) AS definition,
            (
              SELECT string_agg(attributes.attname, ',' ORDER BY selected.ordinality)
              FROM unnest(triggers.tgattr::smallint[]) WITH ORDINALITY AS selected(attnum, ordinality)
              INNER JOIN pg_attribute AS attributes
                ON attributes.attrelid = triggers.tgrelid
               AND attributes.attnum = selected.attnum
            ) AS update_columns
          FROM pg_trigger AS triggers
          INNER JOIN pg_class AS tables
            ON tables.oid = triggers.tgrelid
          INNER JOIN pg_namespace AS table_namespaces
            ON table_namespaces.oid = tables.relnamespace
          INNER JOIN pg_proc AS procedures
            ON procedures.oid = triggers.tgfoid
          INNER JOIN pg_namespace AS procedure_namespaces
            ON procedure_namespaces.oid = procedures.pronamespace
          WHERE table_namespaces.nspname = current_schema()
            AND tables.relname = 'forum_messages'
            AND triggers.tgname = 'forum_messages_require_current_revision'
            AND NOT triggers.tgisinternal
          LIMIT 1
        SQL
        return false unless row

        enabled = row.fetch("tgenabled") == "O"
        row_after_insert_update = row.fetch("tgtype").to_i == 21
        deferred = ActiveModel::Type::Boolean.new.cast(row.fetch("tgdeferrable")) &&
                   ActiveModel::Type::Boolean.new.cast(row.fetch("tginitdeferred"))
        constraint = ActiveModel::Type::Boolean.new.cast(row.fetch("constraint_trigger"))
        columns = row.fetch("update_columns").to_s.split(",").sort == %w[body revision]
        function = row.fetch("function_name") == "forum_messages_require_current_revision" &&
                   row.fetch("function_schema") == row.fetch("current_schema")
        function_definition = row.fetch("function_definition")
        function_body = [
          "NEW.revision <> OLD.revision + 1",
          "forum_message_revision_backfill_queue",
          "digest(convert_to(NEW.body, 'UTF8'), 'sha256')"
        ].all? { |marker| function_definition.include?(marker) }
        definition = row.fetch("definition").include?("EXECUTE FUNCTION forum_messages_require_current_revision()")

        enabled && row_after_insert_update && deferred && constraint && columns &&
          function && function_body && definition
      end

      def install_contract_trigger
        @connection.execute <<~SQL
          CREATE OR REPLACE FUNCTION forum_messages_require_current_revision()
          RETURNS trigger
          LANGUAGE plpgsql
          AS $$
          BEGIN
            IF TG_OP = 'UPDATE'
               AND (
                 NEW.body IS DISTINCT FROM OLD.body
                 OR NEW.revision IS DISTINCT FROM OLD.revision
               )
               AND NEW.revision <> OLD.revision + 1 THEN
              RAISE EXCEPTION 'forum message body changes require the next revision';
            END IF;

            IF NOT EXISTS (
              SELECT 1
              FROM forum_message_revisions
              WHERE forum_message_id = NEW.id
                AND revision = NEW.revision
                AND content_digest = encode(
                  digest(convert_to(NEW.body, 'UTF8'), 'sha256'),
                  'hex'
                )
            ) THEN
              RAISE EXCEPTION 'forum message current revision is missing or mismatched';
            END IF;
            IF EXISTS (
              SELECT 1
              FROM forum_message_revision_backfill_queue
              WHERE forum_message_id = NEW.id
                AND revision = NEW.revision
            ) THEN
              RAISE EXCEPTION 'forum message revision was not written in this transaction';
            END IF;
            RETURN NEW;
          END;
          $$;

          DROP TRIGGER IF EXISTS forum_messages_require_current_revision ON forum_messages;
          CREATE CONSTRAINT TRIGGER forum_messages_require_current_revision
          AFTER INSERT OR UPDATE OF body, revision ON forum_messages
          DEFERRABLE INITIALLY DEFERRED
          FOR EACH ROW
          EXECUTE FUNCTION forum_messages_require_current_revision();
        SQL
      end

      def with_statement_timeout
        previous = @connection.select_value("SHOW statement_timeout")
        @connection.execute("SET statement_timeout = #{@connection.quote(@statement_timeout)}")
        yield
      ensure
        @connection.execute("SET statement_timeout = #{@connection.quote(previous)}") if previous
      end
    end
  end
end
