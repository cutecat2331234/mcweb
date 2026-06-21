# frozen_string_literal: true

class AddCompletedEffectsToIntegrationActionLogs < ActiveRecord::Migration[8.0]
  def change
    add_column :minecraft_integration_action_logs, :completed_effects, :jsonb, default: [], null: false
  end
end
