# frozen_string_literal: true

class AllowAutomaticMinecraftPrimaryAccountSuccessors < ActiveRecord::Migration[8.1]
  def change
    remove_check_constraint :minecraft_primary_account_change_events,
                            name: "mc_primary_events_source"
    add_check_constraint :minecraft_primary_account_change_events,
                         "change_source IN ('player_immediate', 'staff_approval', " \
                         "'administrator_override', 'automatic_successor')",
                         name: "mc_primary_events_source"
  end
end
