# frozen_string_literal: true

class AddMinecraftNodeMetricSnapshots < ActiveRecord::Migration[8.0]
  def change
    create_table :minecraft_node_metric_snapshots do |t|
      t.references :minecraft_node, null: false, foreign_key: true
      t.references :minecraft_server, foreign_key: true
      t.float :cpu_percent
      t.bigint :mem_used_bytes
      t.bigint :mem_total_bytes
      t.bigint :disk_used_bytes
      t.bigint :disk_total_bytes
      t.float :tps
      t.integer :online_players
      t.integer :max_players
      t.jsonb :metadata, default: {}, null: false
      t.datetime :recorded_at, null: false

      t.timestamps
    end

    add_index :minecraft_node_metric_snapshots, %i[minecraft_node_id recorded_at]
    add_index :minecraft_node_metric_snapshots, %i[minecraft_server_id recorded_at]
  end
end
