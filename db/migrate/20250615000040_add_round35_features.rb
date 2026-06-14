# frozen_string_literal: true

class AddRound35Features < ActiveRecord::Migration[8.0]
  def change
    add_column :forum_sections, :allowed_tag_ids, :jsonb, default: [], null: false
    add_column :forum_sections, :prefix_required, :boolean, default: false, null: false
  end
end
