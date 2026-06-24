# frozen_string_literal: true

class AddTierToForumBadges < ActiveRecord::Migration[8.1]
  def change
    add_column :forum_badges, :tier, :string, null: false, default: "bronze"
  end
end
