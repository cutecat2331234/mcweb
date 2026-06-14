# frozen_string_literal: true

class AddReasonCodeToForumReports < ActiveRecord::Migration[8.0]
  def change
    add_column :forum_reports, :reason_code, :string
    add_index :forum_reports, :reason_code
  end
end
