# frozen_string_literal: true

class AddRound107Features < ActiveRecord::Migration[8.1]
  def up
    add_column :forum_user_warnings, :expires_at, :datetime
    add_index :forum_user_warnings, :expires_at

    add_column :forum_sections, :login_required, :boolean, default: false, null: false

    reversible do |dir|
      dir.up do
        say_with_time "normalize forum section prefixes" do
          execute <<~SQL.squish
            UPDATE forum_sections
            SET prefixes = (
              SELECT COALESCE(jsonb_agg(
                CASE
                  WHEN jsonb_typeof(elem) = 'string' THEN jsonb_build_object('name', elem, 'color_hex', NULL)
                  ELSE elem
                END
              ), '[]'::jsonb)
              FROM jsonb_array_elements(prefixes) AS elem
            )
            WHERE prefixes IS NOT NULL AND jsonb_array_length(prefixes) > 0
          SQL
        end
      end
    end
  end

  def down
    remove_index :forum_user_warnings, :expires_at
    remove_column :forum_user_warnings, :expires_at
    remove_column :forum_sections, :login_required
  end
end
