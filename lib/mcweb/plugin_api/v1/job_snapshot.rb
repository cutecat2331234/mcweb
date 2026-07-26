# frozen_string_literal: true

require_relative "normalizer"

module Mcweb
  module PluginApi
    module V1
      module JobSnapshot
        SCHEMA_VERSION = "1"

        module_function

        def run(record, idempotent: false)
          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "plugin.job_run",
            public_id: record.public_id,
            owner_plugin_id: record.owner_plugin_id,
            plugin_version: record.plugin_version,
            job_key: record.job_key,
            qualified_job_key: "#{record.owner_plugin_id}:#{record.job_key}",
            contribution_schema_version: record.contribution_schema_version,
            declaration_digest: record.declaration_digest,
            payload_digest: record.payload_digest,
            status: record.status,
            attempts: record.attempts,
            max_attempts: record.max_attempts,
            scheduled_at: record.scheduled_at,
            enqueued_at: record.enqueued_at,
            started_at: record.started_at,
            finished_at: record.finished_at,
            last_error_code: record.last_error_code,
            last_enqueue_error_code: record.last_enqueue_error_code,
            idempotent: idempotent == true,
            created_at: record.created_at,
            updated_at: record.updated_at
          )
        end
      end
    end
  end
end
