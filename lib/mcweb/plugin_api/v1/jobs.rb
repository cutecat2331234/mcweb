# frozen_string_literal: true

require "json"
require_relative "job_snapshot"
require_relative "result"
require_relative "../../plugins/job_contribution"
require_relative "../../plugins/job_store"

module Mcweb
  module PluginApi
    module V1
      class Jobs
        READ_CAPABILITY = "plugin.jobs.read"
        ENQUEUE_CAPABILITY = "plugin.jobs.enqueue"

        attr_reader :declaration

        def initialize(manifest:, capability_auditor: nil)
          @capability_auditor = capability_auditor
          @plugin_id = manifest.id
          @declaration = Mcweb::Plugins::JobContributionLoader.load(manifest)
          @store = if declaration
            Mcweb::Plugins::JobStore.new(
              plugin_id: manifest.id,
              plugin_version: manifest.version,
              contribution: declaration
            )
          end
          freeze
        end

        def descriptor
          audit(READ_CAPABILITY)
          return declaration_missing_result unless declaration

          Result.success(declaration.to_h)
        rescue StandardError => e
          safe_failure(e)
        end

        def enqueue(job_key:, arguments:, idempotency_key:, wait_seconds: 0)
          audit(ENQUEUE_CAPABILITY)
          return declaration_missing_result unless declaration

          operation = @store.enqueue(
            job_key:,
            arguments:,
            idempotency_key:,
            wait_seconds:
          )
          Result.success(
            JobSnapshot.run(
              operation.record.reload,
              idempotent: operation.idempotent
            )
          )
        rescue Mcweb::Plugins::JobValidationError => e
          validation_failure(e)
        rescue StandardError => e
          safe_failure(e, job_key:)
        end

        def find(public_id:)
          audit(READ_CAPABILITY)
          return declaration_missing_result unless declaration

          Result.success(JobSnapshot.run(@store.find(public_id:)))
        rescue Mcweb::Plugins::JobValidationError => e
          validation_failure(e)
        rescue StandardError => e
          safe_failure(e, public_id:)
        end

        def list(status: nil, limit: 50)
          audit(READ_CAPABILITY)
          return declaration_missing_result unless declaration

          Result.success(
            @store.list(status:, limit:).map { |record| JobSnapshot.run(record) }
          )
        rescue Mcweb::Plugins::JobValidationError => e
          validation_failure(e)
        rescue StandardError => e
          safe_failure(e)
        end

        def cancel(public_id:)
          audit(ENQUEUE_CAPABILITY)
          return declaration_missing_result unless declaration

          Result.success(JobSnapshot.run(@store.cancel(public_id:)))
        rescue Mcweb::Plugins::JobValidationError => e
          validation_failure(e)
        rescue StandardError => e
          safe_failure(e, public_id:)
        end

        def resume(public_id:)
          audit(ENQUEUE_CAPABILITY)
          return declaration_missing_result unless declaration

          Result.success(JobSnapshot.run(@store.resume(public_id:).reload))
        rescue Mcweb::Plugins::JobValidationError => e
          validation_failure(e)
        rescue StandardError => e
          safe_failure(e, public_id:)
        end

        private

        def declaration_missing_result
          Result.failure(
            code: "jobs_not_declared",
            error: "plugin does not declare background jobs"
          )
        end

        def validation_failure(error)
          Result.failure(
            code: error.code,
            error: error.message,
            errors: error.errors
          )
        end

        def safe_failure(error, job_key: nil, public_id: nil)
          log_safe_failure(error, job_key:, public_id:)
          Result.failure(
            code: "host_error",
            error: "plugin jobs operation failed"
          )
        end

        def log_safe_failure(error, job_key:, public_id:)
          return unless defined?(Rails) && Rails.respond_to?(:logger)

          Rails.logger.error(
            JSON.generate(
              {
                event: "plugin_job.host_error",
                plugin_id: @plugin_id,
                job_key: safe_job_key(job_key),
                public_id: safe_public_id(public_id),
                error_class: error.class.name
              }.compact
            )
          )
        rescue StandardError
          nil
        end

        def safe_job_key(value)
          key = value.to_s
          key if declaration&.jobs&.key?(key)
        end

        def safe_public_id(value)
          public_id = value.to_s
          return unless public_id.match?(
            /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/
          )

          public_id
        end

        def audit(capability)
          @capability_auditor&.call(capability)
        end
      end
    end
  end
end
