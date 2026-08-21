# frozen_string_literal: true

require Rails.root.join("lib/mcweb/migrations/check_constraint_contract")

# Structural contract phase. Validation scans do not block ordinary reads or
# writes; NOT NULL changes reuse a validated temporary check so only a brief
# metadata lock is needed. Cross-table MessageRevision completeness is finalized
# after the new dual-writing application is live via the explicit contract task.
class ContractCommunitySelfServiceFoundation < ActiveRecord::Migration[8.1]
  include Mcweb::Migrations::CheckConstraintContract

  disable_ddl_transaction!

  CHECK_CONSTRAINTS = Mcweb::Migrations::CheckConstraintContract::FEATURE_CHECK_CONSTRAINTS

  FOREIGN_KEYS = [
    [ :forum_report_evidences, :forum_reports, :forum_report_id ],
    [ :forum_message_revisions, :forum_messages, :forum_message_id ],
    [ :forum_message_revisions, :users, :editor_id ],
    [ :forum_message_revision_backfill_queue, :forum_messages, :forum_message_id ],
    [ :forum_post_attachments, :forum_messages, :forum_message_id ]
  ].freeze

  NOT_NULL_COLUMNS = [
    [ :forum_messages, :revision, "forum_messages_revision_not_null" ],
    [
      :forum_message_revision_backfill_queue,
      :revision,
      "forum_message_revision_queue_revision_not_null"
    ],
    [
      :forum_message_revision_backfill_queue,
      :body_digest,
      "forum_message_revision_queue_digest_not_null"
    ],
    [ :forum_message_drafts, :attachment_ids, "forum_message_drafts_attachment_ids_not_null" ],
    [ :forum_posts, :revision, "forum_posts_revision_not_null" ],
    [ :forum_profile_posts, :revision, "forum_profile_posts_revision_not_null" ],
    [ :forum_profile_post_comments, :revision, "forum_profile_post_comments_revision_not_null" ]
  ].freeze

  def up
    validate_checks
    validate_foreign_keys
    NOT_NULL_COLUMNS.each { |table, column, name| enforce_not_null(table, column, name) }
    say "Post-deploy: drain old processes, then run db:community_message_revisions:finalize"
  end

  def down
    drop_message_revision_contract
    NOT_NULL_COLUMNS.reverse_each { |table, column, name| relax_not_null(table, column, name) }
  end

  private

  def validate_checks
    CHECK_CONSTRAINTS.each do |table, definitions|
      definitions.each do |name, expression|
        validate_named_check_constraint(table, name: name, expression: expression)
      end
    end
  end

  def validate_foreign_keys
    FOREIGN_KEYS.each do |from_table, to_table, column|
      next unless foreign_key_exists?(from_table, to_table, column: column)

      validate_foreign_key from_table, to_table, column: column
    end
  end

  def enforce_not_null(table, column, temporary_constraint)
    return unless column_exists?(table, column)

    expression = "#{connection.quote_column_name(column)} IS NOT NULL"
    column_definition = connection.columns(table).find { |item| item.name == column.to_s }
    unless column_definition&.null
      # A previous non-transactional run may have committed the metadata change
      # and failed before removing its helper constraint.
      existing = named_check_constraint(table, temporary_constraint)
      assert_check_definition!(table, temporary_constraint, expression, existing) if existing
      remove_check_constraint table, name: temporary_constraint, if_exists: true
      return
    end

    validate_named_check_constraint(
      table,
      name: temporary_constraint,
      expression: expression
    )
    change_column_null table, column, false
    remove_check_constraint table, name: temporary_constraint, if_exists: true
  end

  def relax_not_null(table, column, temporary_constraint)
    return unless column_exists?(table, column)

    expression = "#{connection.quote_column_name(column)} IS NOT NULL"
    existing = named_check_constraint(table, temporary_constraint)
    assert_check_definition!(table, temporary_constraint, expression, existing) if existing
    unless connection.columns(table).find { |item| item.name == column.to_s }&.null
      change_column_null table, column, true
    end
    remove_check_constraint table, name: temporary_constraint, if_exists: true
  end

  def drop_message_revision_contract
    execute "DROP TRIGGER IF EXISTS forum_messages_require_current_revision ON forum_messages"
    execute "DROP FUNCTION IF EXISTS forum_messages_require_current_revision()"
  end
end
