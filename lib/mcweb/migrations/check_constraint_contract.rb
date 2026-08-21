# frozen_string_literal: true

module Mcweb
  module Migrations
    # Makes non-transactional CHECK creation and validation safely restartable.
    # A same-named constraint on another table, or one with a different
    # expression, is never accepted as proof that the requested invariant exists.
    module CheckConstraintContract
      FEATURE_CHECK_CONSTRAINTS = {
        forum_reports: {
          "forum_reports_dedupe_key_format" => "dedupe_key IS NULL OR dedupe_key ~ '^[0-9a-f]{64}$'"
        },
        forum_report_evidences: {
          "forum_report_evidences_positive_revision" => "subject_revision > 0",
          "forum_report_evidences_digest_format" => "content_digest ~ '^[0-9a-f]{64}$'"
        },
        forum_messages: {
          "forum_messages_positive_revision" => "revision > 0"
        },
        forum_message_revisions: {
          "forum_message_revisions_positive_revision" => "revision > 0",
          "forum_message_revisions_digest_format" => "content_digest ~ '^[0-9a-f]{64}$'"
        },
        forum_message_revision_backfill_queue: {
          "forum_message_revision_queue_positive_revision" => "revision > 0",
          "forum_message_revision_queue_digest_format" => "body_digest ~ '^[0-9a-f]{64}$'"
        },
        forum_post_attachments: {
          "forum_post_attachments_single_parent" =>
            "NOT (forum_post_id IS NOT NULL AND forum_message_id IS NOT NULL)"
        },
        forum_posts: {
          "forum_posts_positive_revision" => "revision > 0"
        },
        forum_profile_posts: {
          "forum_profile_posts_positive_revision" => "revision > 0"
        },
        forum_profile_post_comments: {
          "forum_profile_post_comments_positive_revision" => "revision > 0"
        }
      }.freeze

      def ensure_named_check_constraint(table, name:, expression:)
        existing = named_check_constraint(table, name)
        assert_check_definition!(table, name, expression, existing) if existing

        unless existing
          add_check_constraint table,
            expression,
            name: name,
            validate: false
          existing = named_check_constraint(table, name)
          assert_check_definition!(table, name, expression, existing)
        end

        existing
      end

      def validate_named_check_constraint(table, name:, expression:)
        existing = ensure_named_check_constraint(table, name: name, expression: expression)
        unless ActiveModel::Type::Boolean.new.cast(existing.fetch("validated"))
          validate_check_constraint table, name: name
        end

        validated = named_check_constraint(table, name)
        assert_check_definition!(table, name, expression, validated)
        return validated if ActiveModel::Type::Boolean.new.cast(validated.fetch("validated"))

        raise ActiveRecord::MigrationError,
          "CHECK #{table}.#{name} was not validated"
      end

      def named_check_constraint(table, name)
        connection.select_one(<<~SQL.squish)
          SELECT
            pg_get_expr(constraints.conbin, constraints.conrelid) AS expression,
            constraints.convalidated AS validated
          FROM pg_constraint AS constraints
          INNER JOIN pg_class AS tables
            ON tables.oid = constraints.conrelid
          INNER JOIN pg_namespace AS namespaces
            ON namespaces.oid = tables.relnamespace
          WHERE constraints.contype = 'c'
            AND namespaces.nspname = current_schema()
            AND tables.relname = #{connection.quote(table.to_s)}
            AND constraints.conname = #{connection.quote(name.to_s)}
          LIMIT 1
        SQL
      end

      def assert_check_definition!(table, name, expected_expression, actual)
        unless actual
          raise ActiveRecord::MigrationError,
            "CHECK #{table}.#{name} is missing"
        end

        expected = normalize_check_expression(expected_expression)
        observed = normalize_check_expression(actual.fetch("expression"))
        return if expected == observed

        raise ActiveRecord::MigrationError,
          "CHECK #{table}.#{name} has an unexpected definition"
      end

      private

      # PostgreSQL adds harmless parentheses and scalar casts to pg_get_expr.
      # The feature constraints use only scalar predicates, so removing those
      # parser decorations yields a stable comparison without weakening names or
      # table ownership.
      def normalize_check_expression(expression)
        expression
          .to_s
          .downcase
          .gsub(/::(?:text|character varying|integer|bigint)/, "")
          .gsub(/[\s()\"]/, "")
      end
    end
  end
end
