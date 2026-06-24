# frozen_string_literal: true

class CreateForumWarningTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :forum_warning_templates do |t|
      t.string :name, null: false
      t.text :reason, null: false, default: ""
      t.integer :points, null: false, default: 1
      t.integer :expire_days
      t.integer :position, null: false, default: 0

      t.timestamps
    end
  end
end
