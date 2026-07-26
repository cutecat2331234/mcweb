# frozen_string_literal: true

require "digest"
require "json"
require "openssl"
require_relative "job_contribution"

module Mcweb
  module Plugins
    class JobStore
      Operation = Data.define(:record, :idempotent)

      MAX_DELAY_SECONDS = 31_536_000
      MAX_LIST_LIMIT = 100
      PAYLOAD_DIGEST_VERSION = 2
      PAYLOAD_DIGEST_DOMAIN = "mcweb:plugin-job:payload-digest:v2\0".b.freeze

      attr_reader :plugin_id, :plugin_version, :contribution

      def initialize(plugin_id:, plugin_version:, contribution:)
        @plugin_id = plugin_id.to_s.freeze
        @plugin_version = plugin_version.to_s.freeze
        @contribution = contribution
        unless contribution.is_a?(JobContribution) && contribution.plugin_id == @plugin_id
          raise ArgumentError, "jobs contribution does not belong to the requested plugin"
        end
      end

      def enqueue(job_key:, arguments:, idempotency_key:, wait_seconds: 0)
        declaration = contribution.fetch(job_key)
        normalized_arguments = declaration.validate_arguments(arguments)
        normalized_idempotency_key = normalize_idempotency_key(idempotency_key)
        delay = normalize_delay(wait_seconds)
        payload_digest = digest_payload(
          declaration:,
          arguments: normalized_arguments,
          idempotency_key: normalized_idempotency_key,
          wait_seconds: delay
        )
        created = false
        record = PluginJobRun.transaction(requires_new: true) do
          acquire_advisory_lock!(declaration.key, normalized_idempotency_key)
          existing = PluginJobRun.find_by(
            owner_plugin_id: plugin_id,
            job_key: declaration.key,
            idempotency_key: normalized_idempotency_key
          )
          if existing
            assert_idempotent_payload!(existing, payload_digest)
            next existing
          end

          created = true
          PluginJobRun.create!(
            owner_plugin_id: plugin_id,
            plugin_version:,
            job_key: declaration.key,
            contribution_schema_version: contribution.version,
            declaration_digest: declaration.digest,
            arguments: normalized_arguments,
            payload_digest:,
            payload_digest_version: PAYLOAD_DIGEST_VERSION,
            idempotency_key: normalized_idempotency_key,
            status: "queued",
            attempts: 0,
            max_attempts: declaration.max_attempts,
            retry_wait_seconds: declaration.retry_wait_seconds,
            lease_seconds: declaration.lease_seconds,
            requested_wait_seconds: delay,
            scheduled_at: Time.current + delay.seconds
          )
        end
        schedule_after_commit(record) if created
        Operation.new(record:, idempotent: !created)
      rescue Lockbox::DecryptionError
        raise unreadable_arguments_error
      end

      def find(public_id:)
        owned_record!(public_id)
      end

      def list(status: nil, limit: 50)
        bounded_limit = normalize_limit(limit)
        scope = PluginJobRun.owned_by(plugin_id).newest_first
        if status.present?
          normalized_status = status.to_s
          unless PluginJobRun::STATUSES.include?(normalized_status)
            raise JobValidationError.new(
              code: "invalid_argument",
              message: "plugin job status is invalid"
            )
          end
          scope = scope.where(status: normalized_status)
        end
        scope.limit(bounded_limit).to_a.freeze
      end

      def cancel(public_id:)
        record = owned_record!(public_id)
        record.with_lock do
          case record.status
          when "cancelled"
            next record
          when "queued", "retrying", "paused"
            record.update!(
              status: "cancelled",
              finished_at: Time.current,
              lease_expires_at: nil,
              last_error_code: "cancelled_by_plugin"
            )
          when "running"
            raise JobValidationError.new(
              code: "job_running",
              message: "a running plugin job cannot be cancelled"
            )
          else
            raise JobValidationError.new(
              code: "invalid_job_state",
              message: "the plugin job is already complete"
            )
          end
        end
        record
      end

      def resume(public_id:)
        record = owned_record!(public_id)
        declaration = contribution.fetch(record.job_key)
        assert_current_declaration!(record, declaration)
        record.with_lock do
          unless record.status == "paused"
            raise JobValidationError.new(
              code: "invalid_job_state",
              message: "only a paused plugin job can be resumed"
            )
          end
          if record.attempts >= record.max_attempts
            raise JobValidationError.new(
              code: "attempts_exhausted",
              message: "the plugin job has exhausted its automatic attempts"
            )
          end
          record.update!(
            status: "queued",
            scheduled_at: Time.current,
            finished_at: nil,
            lease_expires_at: nil,
            last_error_code: nil
          )
        end
        schedule_after_commit(record)
        record
      end

      private

      def owned_record!(public_id)
        normalized = normalize_public_id(public_id)
        PluginJobRun.owned_by(plugin_id).find_by(public_id: normalized) || raise(
          JobValidationError.new(
            code: "not_found",
            message: "plugin job run was not found"
          )
        )
      end

      def normalize_public_id(value)
        public_id = value.to_s
        unless public_id.match?(/\A[0-9a-f-]{36}\z/)
          raise JobValidationError.new(
            code: "invalid_argument",
            message: "plugin job run id is invalid"
          )
        end
        public_id
      end

      def normalize_idempotency_key(value)
        key = value.to_s
        unless key.length.between?(1, 191) &&
            key.match?(PluginJobRun::IDEMPOTENCY_KEY_PATTERN)
          raise JobValidationError.new(
            code: "invalid_argument",
            message: "plugin job idempotency key is invalid"
          )
        end
        key.freeze
      end

      def normalize_delay(value)
        unless value.is_a?(Integer) && value.between?(0, MAX_DELAY_SECONDS)
          raise JobValidationError.new(
            code: "invalid_argument",
            message: "plugin job wait_seconds is outside the supported range"
          )
        end
        value
      end

      def normalize_limit(value)
        limit = Integer(value, exception: false)
        unless limit&.between?(1, MAX_LIST_LIMIT)
          raise JobValidationError.new(
            code: "invalid_argument",
            message: "plugin job list limit is invalid"
          )
        end
        limit
      end

      def digest_payload(declaration:, arguments:, idempotency_key:, wait_seconds:)
        canonical_payload = JSON.generate(
          {
            "plugin_id" => plugin_id,
            "plugin_version" => plugin_version,
            "job_key" => declaration.key,
            "contribution_schema_version" => contribution.version,
            "declaration_digest" => declaration.digest,
            "arguments" => arguments.sort.to_h,
            "idempotency_key" => idempotency_key,
            "wait_seconds" => wait_seconds
          }
        )
        key = Lockbox.attribute_key(
          table: "plugin_job_runs",
          attribute: "payload_digest",
          encode: false
        )
        OpenSSL::HMAC.hexdigest(
          "SHA256",
          key,
          PAYLOAD_DIGEST_DOMAIN + canonical_payload.b
        )
      end

      def assert_idempotent_payload!(record, payload_digest)
        return if record.payload_digest == payload_digest

        raise JobValidationError.new(
          code: "idempotency_conflict",
          message: "plugin job idempotency key was already used for different work"
        )
      end

      def assert_current_declaration!(record, declaration)
        return if record.plugin_version == plugin_version &&
          record.contribution_schema_version == contribution.version &&
          record.declaration_digest == declaration.digest

        raise JobValidationError.new(
          code: "incompatible_job",
          message: "plugin job belongs to a different plugin or declaration version"
        )
      end

      def acquire_advisory_lock!(job_key, idempotency_key)
        connection = PluginJobRun.connection
        return unless connection.adapter_name.match?(/postgres/i)

        key = Digest::SHA256
          .digest("mcweb:plugin-job:#{plugin_id}:#{job_key}:#{idempotency_key}")
          .unpack1("q>")
        bind = ActiveRecord::Relation::QueryAttribute.new(
          "plugin_job_advisory_lock_key",
          key,
          ActiveRecord::Type::Integer.new(limit: 8)
        )
        connection.exec_query(
          "SELECT pg_advisory_xact_lock($1)::text",
          "Plugin job advisory lock",
          [ bind ]
        )
      end

      def schedule_after_commit(record)
        public_id = record.public_id
        scheduled_at = record.scheduled_at
        ActiveRecord.after_all_transactions_commit do
          self.class.schedule!(public_id:, scheduled_at:)
        end
      end

      def unreadable_arguments_error
        JobValidationError.new(
          code: "job_payload_unreadable",
          message: "plugin job arguments could not be decrypted"
        )
      end

      class << self
        def schedule!(public_id:, scheduled_at:)
          job = PluginOwnedJob.set(wait_until: scheduled_at).perform_later(public_id)
          now = Time.current
          PluginJobRun
            .where(public_id:, status: %w[queued retrying running])
            .update_all(
              active_job_id: job.job_id,
              enqueued_at: now,
              recovery_claimed_at: now,
              last_enqueue_error_code: nil,
              updated_at: now
            )
          job
        rescue StandardError => e
          log_enqueue_failure(public_id, e)
          now = Time.current
          PluginJobRun
            .where(public_id:, status: %w[queued retrying running])
            .update_all(
              recovery_claimed_at: now,
              last_enqueue_error_code: "enqueue_failed",
              updated_at: now
            )
          nil
        end

        private

        def log_enqueue_failure(public_id, error)
          return unless defined?(Rails) && Rails.respond_to?(:logger)

          record = PluginJobRun
            .select(:owner_plugin_id, :job_key, :public_id)
            .find_by(public_id:)
          Rails.logger.error(
            {
              event: "plugin_job.enqueue_failed",
              plugin_id: record&.owner_plugin_id,
              job_key: record&.job_key,
              public_id: record&.public_id || public_id.to_s,
              error_class: error.class.name
            }.compact.to_json
          )
        rescue StandardError
          nil
        end
      end
    end
  end
end
