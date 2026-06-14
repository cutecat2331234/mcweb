# frozen_string_literal: true

class AddRound34Features < ActiveRecord::Migration[8.0]
  def change
    add_column :forum_sections, :required_tag_ids, :jsonb, default: [], null: false
  end
end
