# frozen_string_literal: true

class AddRound53Features < ActiveRecord::Migration[8.1]
  def change
    add_column :forum_sections, :default_tag_ids, :jsonb, default: [], null: false
  end
end
