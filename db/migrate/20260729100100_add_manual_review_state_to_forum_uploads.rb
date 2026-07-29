# frozen_string_literal: true

class AddManualReviewStateToForumUploads < ActiveRecord::Migration[8.0]
  def change
    add_column :forum_uploads, :manual_review_status, :string, null: false, default: "none"
    add_column :forum_uploads, :manual_review_version, :integer, null: false, default: 0
    add_column :forum_uploads, :manual_reviewed_at, :datetime
    add_column :forum_uploads, :manual_review_source_result_code, :string
    add_column :forum_uploads, :manual_review_file_sha256, :string
    add_column :forum_uploads, :manual_review_revoked_at, :datetime
    add_reference :forum_uploads,
                  :manual_reviewed_by,
                  foreign_key: { to_table: :users, on_delete: :nullify },
                  index: true
    add_reference :forum_uploads,
                  :manual_review_revoked_by,
                  foreign_key: { to_table: :users, on_delete: :nullify },
                  index: true

    add_index :forum_uploads, :manual_review_status
    add_check_constraint :forum_uploads,
                         "manual_review_status IN ('none', 'released', 'revoked')",
                         name: "forum_uploads_valid_manual_review_status"
    add_check_constraint :forum_uploads,
                         "manual_review_version >= 0",
                         name: "forum_uploads_nonnegative_manual_review_version"
  end
end
