# frozen_string_literal: true

class EncryptPluginJobRunArguments < ActiveRecord::Migration[8.0]
  class MigrationPluginJobRun < ActiveRecord::Base
    self.table_name = "plugin_job_runs"

    has_encrypted :arguments,
      type: :json,
      encrypted_attribute: :encrypted_arguments
  end

  def up
    rename_column :plugin_job_runs, :arguments, :legacy_arguments
    add_column :plugin_job_runs, :encrypted_arguments, :text
    MigrationPluginJobRun.reset_column_information

    MigrationPluginJobRun.find_each do |record|
      plaintext = record.read_attribute(:legacy_arguments)
      record.arguments = plaintext
      record.save!(validate: false)
      record.reload
      unless record.encrypted_arguments.present? && record.arguments == plaintext
        raise "plugin job arguments encryption verification failed for row #{record.id}"
      end
    end

    change_column_null :plugin_job_runs, :encrypted_arguments, false
    remove_column :plugin_job_runs, :legacy_arguments, :jsonb
    MigrationPluginJobRun.reset_column_information
  end

  def down
    add_column :plugin_job_runs, :legacy_arguments, :jsonb
    MigrationPluginJobRun.reset_column_information

    MigrationPluginJobRun.find_each do |record|
      plaintext = record.arguments
      record.update_column(:legacy_arguments, plaintext)
      unless record.reload.read_attribute(:legacy_arguments) == plaintext
        raise "plugin job arguments rollback verification failed for row #{record.id}"
      end
    end

    change_column_null :plugin_job_runs, :legacy_arguments, false
    change_column_default :plugin_job_runs, :legacy_arguments, from: nil, to: {}
    remove_column :plugin_job_runs, :encrypted_arguments, :text
    rename_column :plugin_job_runs, :legacy_arguments, :arguments
    MigrationPluginJobRun.reset_column_information
  end
end
