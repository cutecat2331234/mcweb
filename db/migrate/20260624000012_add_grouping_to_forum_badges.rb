# frozen_string_literal: true

class AddGroupingToForumBadges < ActiveRecord::Migration[8.1]
  def change
    add_column :forum_badges, :grouping, :string, null: false, default: "general"
  end
end
