# frozen_string_literal: true

class RepairMinecraftWorldRestorePlanIndexName < ActiveRecord::Migration[8.1]
  TABLE_NAME = :minecraft_world_restore_plans
  COLUMN_NAME = "minecraft_world_backup_id"
  DESIRED_NAME = "idx_minecraft_restore_plans_world_backup"
  LEGACY_NAME = "index_minecraft_world_restore_plans_on_minecraft_world_backup_i"

  def up
    rename_matching_index(DESIRED_NAME)
  end

  def down
    rename_matching_index(LEGACY_NAME)
  end

  private

  def rename_matching_index(target_name)
    return unless table_exists?(TABLE_NAME)

    matching_index = connection.indexes(TABLE_NAME).find do |index|
      index.columns == [COLUMN_NAME]
    end
    return if matching_index.nil? || matching_index.name == target_name

    rename_index TABLE_NAME, matching_index.name, target_name
  end
end
