# frozen_string_literal: true

require Rails.root.join("lib/mcweb/migrations/community_message_revision_backfill")

# Backfill phase. This migration is intentionally restartable and has no outer
# transaction: every bounded insert batch commits independently. The expand
# migration's queue triggers retain messages written after the last scan.
class BackfillCommunityMessageRevisions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    result = Mcweb::Migrations::CommunityMessageRevisionBackfill.new.call
    say "Encrypted #{result.fetch(:inserted)} message revision snapshots; " \
      "#{result.fetch(:queued)} concurrent messages remain queued"
  end

  # Revisions are audit history and remain intact when rolling back only the
  # backfill phase. The expand migration owns their eventual table removal.
  def down
    say "Retaining encrypted message revision snapshots"
  end
end
