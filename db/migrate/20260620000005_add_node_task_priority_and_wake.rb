# frozen_string_literal: true

class AddNodeTaskPriorityAndWake < ActiveRecord::Migration[8.0]
  def change
    add_column :minecraft_node_tasks, :priority, :string, null: false, default: "normal"
    add_index :minecraft_node_tasks, %i[minecraft_node_id status priority]

    add_column :minecraft_nodes, :tasks_wake_at, :datetime
  end
end
