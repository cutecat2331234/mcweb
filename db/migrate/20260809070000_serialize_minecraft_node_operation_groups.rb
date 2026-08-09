# frozen_string_literal: true

class SerializeMinecraftNodeOperationGroups < ActiveRecord::Migration[8.0]
  def change
    add_column :minecraft_node_operations, :dispatch_slot, :integer
    add_check_constraint :minecraft_node_operations,
      "dispatch_slot IS NULL OR dispatch_slot = 1",
      name: "minecraft_node_operations_dispatch_slot_value"
    add_index :minecraft_node_operations,
      :dispatch_slot,
      unique: true,
      where: "dispatch_slot IS NOT NULL",
      name: "idx_minecraft_node_operations_single_dispatch"
  end
end
