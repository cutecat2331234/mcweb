# frozen_string_literal: true

class AddScheduleToForumNotices < ActiveRecord::Migration[8.1]
  def change
    add_column :forum_notices, :starts_at, :datetime
    add_column :forum_notices, :ends_at, :datetime
  end
end
