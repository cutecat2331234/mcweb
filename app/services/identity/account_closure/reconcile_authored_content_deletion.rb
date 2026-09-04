# frozen_string_literal: true

module Identity
  module AccountClosure
    class ReconcileAuthoredContentDeletion < ApplicationService
      DEFAULT_LIMIT = 100
      DELETE_CONTENT_OUTCOMES = %w[
        authored_content_deletion_queued
        authored_content_deleted
        legally_retained
      ].freeze
      MAX_AUTOMATIC_RECOVERIES = 3
      DEAD_LETTER_RECOVERY_DELAYS = [ 1.hour, 6.hours, 24.hours ].freeze
      RECONCILIATION_EXCLUDED_STATUSES = (
        AuthoredContentDeletion::NON_TERMINAL_STATUSES +
          [ AuthoredContentDeletion::MANUAL_ATTENTION_STATUS ]
      ).freeze

      def initialize(limit: DEFAULT_LIMIT, at: Time.current)
        @limit = Integer(limit, exception: false) || DEFAULT_LIMIT
        @at = at
      end

      def call
        counts = {
          inspected: 0,
          queued: 0,
          requeued: 0,
          recovery_backoff: 0,
          manual_attention: 0,
          resumed: 0,
          skipped: 0,
          failed: 0
        }
        resume_waiting_requests(counts)
        requeue_dead_lettered_intents(counts)
        candidate_users.limit(@limit.clamp(1, 500)).each do |user|
          counts[:inspected] += 1
          outcome = reconcile_user(user)
          counts[outcome] += 1
        rescue StandardError => error
          counts[:failed] += 1
          Rails.logger.error(
            "[identity.account_closure] authored_content_reconciliation_failed " \
            "user_id=#{user.id} error=#{error.class.name}"
          )
        end

        ServiceResult.success(counts)
      end

      private

      def resume_waiting_requests(counts)
        waiting_users.limit(@limit.clamp(1, 500)).each do |user|
          counts[:inspected] += 1
          if resume_waiting_request(user)
            counts[:resumed] += 1
          else
            counts[:skipped] += 1
          end
        rescue StandardError => error
          counts[:failed] += 1
          Rails.logger.error(
            "[identity.account_closure] authored_content_resume_failed " \
            "user_id=#{user.id} error=#{error.class.name}"
          )
        end
      end

      def waiting_users
        path = "account_closure_results #>> " \
          "'{identity.authored_content,details,processing,next_recheck_at}'"
        due_at = "CASE WHEN (#{path}) ~ " \
          "'^[0-9]{4}-[0-9]{2}-[0-9]{2}T' THEN (#{path})::timestamptz " \
          "ELSE '-infinity'::timestamptz END"
        User.where(status: :deleted)
          .where.not(account_closed_at: nil)
          .where(
            "account_closure_results #>> " \
            "'{identity.authored_content,details,processing,status}' = ?",
            AuthoredContentDeletion::WAITING_STATUS
          )
          .where("#{due_at} <= ?", @at)
          .order(Arel.sql("#{due_at} ASC"), :id)
      end

      def resume_waiting_request(user)
        resumed = false
        user.with_lock do
          results = user.account_closure_results.to_h.deep_stringify_keys.deep_dup
          contribution = results.fetch("identity.authored_content", nil)
          next unless contribution

          details = contribution.fetch("details", {}).to_h
          processing = details.fetch("processing", {}).to_h
          next unless processing.fetch("status", nil) == AuthoredContentDeletion::WAITING_STATUS
          next unless recheck_due?(processing.fetch("next_recheck_at", nil))

          request_key = processing.fetch("request_key")
          next_batch = processing.fetch("batch_number", 0).to_i + 1
          prior_blockers = Array(processing.fetch("last_blockers", [])).map(&:to_s)
          processing.merge!(
            "status" => "queued",
            "batch_number" => next_batch,
            "prior_outcome" => user.account_closure_outcome,
            "resource_index" => 0,
            "cursors" => AuthoredContentDeletion.empty_counts,
            "retained_records" => AuthoredContentDeletion.empty_counts,
            "blocker_counts" => {},
            "global_blocker" => false,
            "blocker_recheck_count" =>
              processing.fetch("blocker_recheck_count", 0).to_i + 1,
            "last_resumed_at" => @at.iso8601,
            "updated_at" => @at.iso8601
          )
          processing.delete("next_recheck_at")
          details["processing"] = processing
          contribution["details"] = details
          results["identity.authored_content"] = contribution
          user.update!(account_closure_results: results)
          AuthoredContentDeletion.record_batch!(
            user:,
            request_key:,
            batch_number: next_batch,
            requested_at: @at
          )
          audit = Administration::AuditLogger.call(
            actor: nil,
            action: "identity.account_closure_content_resumed",
            resource: user,
            request_id: Digest::SHA256.hexdigest(
              "#{request_key}:resumed:#{next_batch}"
            ).first(64),
            reason: "account_closure_blocker_recheck_due",
            metadata: {
              prior_blockers:,
              next_batch_number: next_batch,
              blocker_recheck_count: processing.fetch("blocker_recheck_count")
            }
          )
          raise AuthoredContentDeletion::ProcessingError,
                "resume_audit_failed" unless audit.success?

          resumed = true
        end
        resumed
      end

      def requeue_dead_lettered_intents(counts)
        dead_lettered_intents.limit(@limit.clamp(1, 500)).each do |intent|
          counts[:inspected] += 1
          outcome = requeue_dead_lettered_intent(intent)
          counts[outcome] += 1
        rescue StandardError => error
          counts[:failed] += 1
          Rails.logger.error(
            "[identity.account_closure] authored_content_requeue_failed " \
            "intent_id=#{intent.id} error=#{error.class.name}"
          )
        end
      end

      def dead_lettered_intents
        latest_dead_letters = Operations::DurableEnqueueEvent
          .where(event_type: "dead_lettered")
          .where(<<~SQL.squish)
            NOT EXISTS (
              SELECT 1
              FROM operations_durable_enqueue_events later
              WHERE later.intent_id = operations_durable_enqueue_events.intent_id
                AND later.sequence > operations_durable_enqueue_events.sequence
            )
          SQL
          .select(:intent_id, :occurred_at)
        processing_status = "account_closure_users.account_closure_results #>> " \
          "'{identity.authored_content,details,processing,status}'"
        next_recovery_path = "account_closure_users.account_closure_results #>> " \
          "'{identity.authored_content,details,processing,next_recovery_at}'"
        next_recovery_at = "CASE WHEN (#{next_recovery_path}) ~ " \
          "'^[0-9]{4}-[0-9]{2}-[0-9]{2}T' THEN (#{next_recovery_path})::timestamptz " \
          "ELSE '-infinity'::timestamptz END"
        Operations::DurableEnqueueIntent
          .joins(<<~SQL.squish)
            INNER JOIN (#{latest_dead_letters.to_sql}) account_closure_dead_letters
              ON account_closure_dead_letters.intent_id = operations_durable_enqueue_intents.id
          SQL
          .joins(<<~SQL.squish)
            INNER JOIN users account_closure_users
              ON account_closure_users.id = operations_durable_enqueue_intents.source_id
          SQL
          .where(handler_key: AuthoredContentDeletion::HANDLER_KEY)
          .where(<<~SQL.squish)
            NOT EXISTS (
              SELECT 1
              FROM operations_durable_enqueue_intents later_intent
              WHERE later_intent.handler_key = operations_durable_enqueue_intents.handler_key
                AND later_intent.source_kind = operations_durable_enqueue_intents.source_kind
                AND later_intent.source_id = operations_durable_enqueue_intents.source_id
                AND later_intent.id > operations_durable_enqueue_intents.id
            )
          SQL
          .where(
            "(#{processing_status}) IN (?)",
            AuthoredContentDeletion::ACTIVE_STATUSES +
              [ AuthoredContentDeletion::RECOVERY_BACKOFF_STATUS ]
          )
          .where(
            "COALESCE((#{processing_status}), '') <> ? OR (#{next_recovery_at}) <= ?",
            AuthoredContentDeletion::RECOVERY_BACKOFF_STATUS,
            @at
          )
          .order(Arel.sql("account_closure_dead_letters.occurred_at ASC"), :id)
      end

      def requeue_dead_lettered_intent(intent)
        user = User.find_by(id: intent.source_id)
        return :skipped unless user

        outcome = :skipped
        manual_attention_signal = nil
        user.with_lock do
          results = user.account_closure_results.to_h.deep_stringify_keys.deep_dup
          contribution = results.fetch("identity.authored_content", nil)
          next unless contribution

          details = contribution.fetch("details", {}).to_h
          processing = details.fetch("processing", {}).to_h
          request_key = intent.arguments.fetch("request_key", nil)
          batch_number = intent.arguments.fetch("batch_number", 0).to_i
          next unless processing.fetch("request_key", nil) == request_key
          recoverable_statuses = AuthoredContentDeletion::ACTIVE_STATUSES +
            [ AuthoredContentDeletion::RECOVERY_BACKOFF_STATUS ]
          next unless processing.fetch("status", nil).in?(recoverable_statuses)
          next unless processing.fetch("batch_number", 0).to_i == batch_number

          intent.association(:events).reset
          intent.association(:attempts).reset
          state = Operations::DurableEnqueueLedger.state(intent)
          next unless state.status == "dead_lettered"

          recovery_count = processing.fetch("recovery_count", 0).to_i
          if recovery_count >= MAX_AUTOMATIC_RECOVERIES
            manual_attention_signal = mark_manual_attention_locked!(
              user:,
              results:,
              contribution:,
              details:,
              processing:,
              intent:,
              state:
            )
            outcome = :manual_attention
            next
          end

          next_recovery_at = recovery_due_at(
            processing:,
            state:,
            recovery_count:
          )
          if next_recovery_at > @at
            schedule_recovery_backoff_locked!(
              user:,
              results:,
              contribution:,
              details:,
              processing:,
              intent:,
              state:,
              next_recovery_at:
            )
            outcome = :recovery_backoff
            next
          end

          next_batch = batch_number + 1
          processing.merge!(
            "status" => "queued",
            "batch_number" => next_batch,
            "recovery_count" => processing.fetch("recovery_count", 0).to_i + 1,
            "last_requeued_at" => @at.iso8601,
            "last_failed_intent_public_id" => intent.public_id,
            "last_failure_code" => state.last_event&.error_code.to_s.presence ||
              "attempts_exhausted"
          )
          processing.delete("next_recovery_at")
          details["processing"] = processing
          contribution["details"] = details
          results["identity.authored_content"] = contribution
          user.update!(account_closure_results: results)
          AuthoredContentDeletion.record_batch!(
            user:,
            request_key:,
            batch_number: next_batch,
            requested_at: @at
          )
          audit = Administration::AuditLogger.call(
            actor: nil,
            action: "identity.account_closure_content_requeued",
            resource: user,
            request_id: "#{request_key}:#{next_batch}",
            reason: "durable_attempts_exhausted",
            metadata: {
              prior_intent_public_id: intent.public_id,
              prior_batch_number: batch_number,
              next_batch_number: next_batch,
              recovery_count: processing.fetch("recovery_count")
            }
          )
          raise AuthoredContentDeletion::ProcessingError,
                "requeue_audit_failed" unless audit.success?

          outcome = :requeued
        end
        if manual_attention_signal
          ActiveRecord.after_all_transactions_commit do
            emit_manual_attention_signal(manual_attention_signal)
          end
        end
        outcome
      end

      def recovery_due_at(processing:, state:, recovery_count:)
        recorded = processing.fetch("next_recovery_at", nil)
        return Time.iso8601(recorded.to_s) if recorded.present?

        state.last_event.occurred_at + dead_letter_recovery_delay(recovery_count)
      rescue ArgumentError
        state.last_event.occurred_at + dead_letter_recovery_delay(recovery_count)
      end

      def dead_letter_recovery_delay(recovery_count)
        DEAD_LETTER_RECOVERY_DELAYS.fetch(
          [ recovery_count, DEAD_LETTER_RECOVERY_DELAYS.length - 1 ].min
        )
      end

      def schedule_recovery_backoff_locked!(
        user:,
        results:,
        contribution:,
        details:,
        processing:,
        intent:,
        state:,
        next_recovery_at:
      )
        already_scheduled =
          processing.fetch("status", nil) == AuthoredContentDeletion::RECOVERY_BACKOFF_STATUS &&
          processing.fetch("next_recovery_at", nil).present?
        return if already_scheduled

        prior_status = processing.fetch("status", nil)
        processing.merge!(
          "status" => AuthoredContentDeletion::RECOVERY_BACKOFF_STATUS,
          "next_recovery_at" => next_recovery_at.iso8601,
          "last_failed_intent_public_id" => intent.public_id,
          "last_failure_code" => state.last_event&.error_code.to_s.presence ||
            "attempts_exhausted",
          "updated_at" => @at.iso8601
        )
        details["processing"] = processing
        contribution["details"] = details
        results["identity.authored_content"] = contribution
        user.update!(account_closure_results: results)

        audit = Administration::AuditLogger.call(
          actor: nil,
          action: "identity.account_closure_content_recovery_backoff",
          resource: user,
          request_id: Digest::SHA256.hexdigest(
            "#{intent.public_id}:recovery-backoff:#{processing.fetch('recovery_count', 0)}"
          ).first(64),
          reason: "durable_attempts_exhausted",
          metadata: {
            failed_intent_public_id: intent.public_id,
            recovery_count: processing.fetch("recovery_count", 0),
            next_recovery_at: next_recovery_at.iso8601
          },
          before_state: { processing_status: prior_status },
          after_state: {
            processing_status: AuthoredContentDeletion::RECOVERY_BACKOFF_STATUS
          }
        )
        raise AuthoredContentDeletion::ProcessingError,
              "recovery_backoff_audit_failed" unless audit.success?
      end

      def mark_manual_attention_locked!(
        user:,
        results:,
        contribution:,
        details:,
        processing:,
        intent:,
        state:
      )
        prior_status = processing.fetch("status", nil)
        processing.merge!(
          "status" => AuthoredContentDeletion::MANUAL_ATTENTION_STATUS,
          "manual_attention_at" => @at.iso8601,
          "last_failed_intent_public_id" => intent.public_id,
          "last_failure_code" => state.last_event&.error_code.to_s.presence ||
            "attempts_exhausted",
          "updated_at" => @at.iso8601
        )
        processing.delete("next_recovery_at")
        details.merge!(
          "outcome" => "manual_attention_required",
          "processing" => processing
        )
        contribution["details"] = details
        results["identity.authored_content"] = contribution
        user.update!(
          account_closure_outcome: "manual_attention_required",
          account_closure_results: results
        )

        audit = Administration::AuditLogger.call(
          actor: nil,
          action: "identity.account_closure_content_manual_attention",
          resource: user,
          request_id: Digest::SHA256.hexdigest(
            "#{intent.public_id}:manual-attention"
          ).first(64),
          reason: "automatic_recovery_exhausted",
          metadata: {
            failed_intent_public_id: intent.public_id,
            recovery_count: processing.fetch("recovery_count", 0),
            failure_code: processing.fetch("last_failure_code")
          },
          before_state: { processing_status: prior_status },
          after_state: {
            outcome: "manual_attention_required",
            processing_status: AuthoredContentDeletion::MANUAL_ATTENTION_STATUS
          }
        )
        raise AuthoredContentDeletion::ProcessingError,
              "manual_attention_audit_failed" unless audit.success?

        signal_payload = {
          user_public_id: user.public_id,
          intent_public_id: intent.public_id,
          recovery_count: processing.fetch("recovery_count", 0),
          failure_code: processing.fetch("last_failure_code")
        }
        signal_payload
      end

      # Runtime observers are deliberately notified only after the user row and
      # audit transaction commits. Monitoring integrations are external side
      # effects: a broken subscriber must never roll back or misreport the
      # durable manual-attention terminal state.
      def emit_manual_attention_signal(signal_payload)
        begin
          Rails.logger.error(
            "[identity.account_closure] authored_content_manual_attention " \
            "user_public_id=#{signal_payload.fetch(:user_public_id)} " \
            "intent_public_id=#{signal_payload.fetch(:intent_public_id)} " \
            "recovery_count=#{signal_payload.fetch(:recovery_count)} " \
            "failure_code=#{signal_payload.fetch(:failure_code)}"
          )
        rescue StandardError
          nil
        end

        ActiveSupport::Notifications.instrument(
          "identity.account_closure_content.manual_attention",
          **signal_payload
        )
      rescue StandardError => error
        begin
          Rails.logger.error(
            "[identity.account_closure] authored_content_manual_attention_signal_failed " \
            "user_public_id=#{signal_payload[:user_public_id]} " \
            "intent_public_id=#{signal_payload[:intent_public_id]} " \
            "error=#{error.class.name}"
          )
        rescue StandardError
          nil
        end
      end

      def candidate_users
        User.where(status: :deleted)
          .where.not(account_closed_at: nil)
          .where(
            "(account_closure_results #>> " \
            "'{identity.authored_content,details,processing,status}') IS NULL " \
            "OR (account_closure_results #>> " \
            "'{identity.authored_content,details,processing,status}') NOT IN (?)",
            RECONCILIATION_EXCLUDED_STATUSES
          )
          .where(historical_deletion_sql)
          .where(
            "(#{missing_lifecycle_sql}) OR " \
            "(#{active_authored_content_sql}) OR " \
            "(#{topic_scrub_required_sql}) OR " \
            "(#{opening_post_scrub_required_sql}) OR " \
            "(#{profile_post_scrub_required_sql})"
          )
          .order(:id)
      end

      def reconcile_user(user)
        outcome = :skipped
        user.with_lock do
          results = user.account_closure_results.to_h.deep_stringify_keys.deep_dup
          contribution = results.fetch("identity.authored_content", nil)
          next unless contribution

          details = contribution.fetch("details", {}).to_h
          next unless historical_deletion_recorded?(user, details)

          processing = details.fetch("processing", {}).to_h
          next if processing.fetch("status", nil).in?(RECONCILIATION_EXCLUDED_STATUSES)

          active_upper_bounds = retained_upper_bounds(user, details:)
          repair_only = active_upper_bounds.values.none?(&:positive?)
          upper_bounds = repair_only ? repair_upper_bounds(user) : active_upper_bounds
          next unless upper_bounds.values.any?(&:positive?)

          request_key = SecureRandom.uuid
          zero_counts = AuthoredContentDeletion::RESOURCE_KEYS.index_with { 0 }
          initial_deleted_records = if repair_only
            zero_counts
          else
            normalized_existing_counts(details.fetch("deleted_records", {}))
          end
          details["processing"] = {
            "schema_version" => AuthoredContentDeletion::SCHEMA_VERSION,
            "status" => "queued",
            "request_key" => request_key,
            "repair_only" => repair_only,
            "prior_outcome" => user.account_closure_outcome,
            "batch_number" => 1,
            "resource_index" => 0,
            "cursors" => zero_counts,
            "upper_bounds" => upper_bounds,
            "deleted_records" => initial_deleted_records,
            "retained_records" => zero_counts,
            "missing_records" => zero_counts,
            "blocker_counts" => {},
            "requested_at" => @at.iso8601
          }
          details["closure_mode"] = "delete_content"
          contribution["details"] = details
          results["identity.authored_content"] = contribution
          user.update!(account_closure_results: results)
          AuthoredContentDeletion.record_batch!(
            user:,
            request_key:,
            batch_number: 1,
            requested_at: @at
          )
          reconciliation_reason = if repair_only
            "repair_missing_content_lifecycle"
          else
            "resume_retained_account_closure_content"
          end
          audit = Administration::AuditLogger.call(
            actor: nil,
            action: "identity.account_closure_content_reconciliation_queued",
            resource: user,
            request_id: request_key,
            reason: reconciliation_reason,
            metadata: {
              upper_bounds:,
              repair_only:,
              lifecycle_schema_version: AuthoredContentDeletion::SCHEMA_VERSION
            }
          )
          raise AuthoredContentDeletion::ProcessingError,
                "reconciliation_audit_failed" unless audit.success?

          outcome = :queued
        end
        outcome
      end

      def historical_deletion_recorded?(user, details)
        return true if details.fetch("closure_mode", nil) == "delete_content"
        return true if user.account_closure_outcome.in?(DELETE_CONTENT_OUTCOMES)
        return true if details.fetch("outcome", nil).in?(DELETE_CONTENT_OUTCOMES)

        details.fetch("deleted_records", {}).to_h.values.sum(&:to_i).positive?
      end

      def retained_upper_bounds(user, details:)
        AuthoredContentContributor::RESOURCE_CONFIG.each_with_object({}) do |(key, config), bounds|
          scope = config.fetch(:model).unscoped.where(user_id: user.id)
          bounds[key] = if key == "topics"
            topic_remediation_scope(user:, details:).maximum(:id).to_i
          elsif key == "profile_posts"
            profile_post_remediation_scope(user:, details:).maximum(:id).to_i
          elsif key == "posts"
            ordinary_posts = scope.where(deleted_at: nil).where.not(floor_number: 1)
            opening_posts = opening_post_remediation_scope(user:, details:)
            ordinary_posts.or(opening_posts).maximum(:id).to_i
          else
            scope.where(deleted_at: nil).maximum(:id).to_i
          end
        end
      end

      def topic_remediation_scope(user:, details:)
        scope = Community::Topic.unscoped.where(user_id: user.id)
        return scope unless details.fetch("topic_titles_scrubbed", false) == true

        replacement = I18n.t("mcweb.identity.deleted_content_title", locale: user.locale)
        unsafe_lifecycle_ids = structural_lifecycle_target_ids(Community::Topic)
        scope.where.not(title: replacement)
          .or(scope.where.not(deleted_at: nil))
          .or(scope.where(id: unsafe_lifecycle_ids))
      end

      def profile_post_remediation_scope(user:, details:)
        scope = Community::ProfilePost.unscoped.where(user_id: user.id)
        return scope unless details.fetch("profile_posts_scrubbed", false) == true

        replacement = I18n.t("mcweb.identity.deleted_content_body", locale: user.locale)
        unsafe_lifecycle_ids = structural_lifecycle_target_ids(Community::ProfilePost)
        scope.where.not(body: replacement)
          .or(scope.where.not(deleted_at: nil))
          .or(scope.where(id: unsafe_lifecycle_ids))
      end

      def opening_post_remediation_scope(user:, details:)
        scope = Community::Post.unscoped.where(user_id: user.id, floor_number: 1)
        return scope unless details.fetch("opening_posts_scrubbed", false) == true

        replacement = I18n.t("mcweb.identity.deleted_content_body", locale: user.locale)
        unsafe_edit_post_ids = Community::PostEdit
          .where(
            "body_before IS NULL OR body_before <> :replacement OR " \
            "body_after IS NULL OR body_after <> :replacement OR " \
            "reason IS NOT NULL",
            replacement:
          )
          .select(:forum_post_id)
        attachment_post_ids = Community::PostAttachment.with_discarded
          .where.not(forum_post_id: nil)
          .select(:forum_post_id)
        upload_post_ids = Community::Upload
          .where(kind: %w[inline_image post_attachment])
          .where.not(forum_post_id: nil)
          .select(:forum_post_id)
        unsafe_lifecycle_ids = structural_lifecycle_target_ids(Community::Post)

        scope.where.not(body: replacement)
          .or(scope.where.not(deleted_at: nil))
          .or(scope.where(id: unsafe_edit_post_ids))
          .or(scope.where(id: attachment_post_ids))
          .or(scope.where(id: upload_post_ids))
          .or(scope.where(id: unsafe_lifecycle_ids))
      end

      def structural_lifecycle_target_ids(model)
        DataGovernance::ContentLifecycleRecord
          .where(
            target_type: model.base_class.name,
            deletion_reason: "account_closure_delete_content"
          )
          .where(<<~SQL.squish, restored: "restored")
            status <> :restored
            OR target_snapshot ? 'label'
            OR target_snapshot #>> '{owner,username}' IS NOT NULL
          SQL
          .select(:target_id)
      end

      def repair_upper_bounds(user)
        AuthoredContentContributor::RESOURCE_CONFIG.each_with_object({}) do |(key, config), bounds|
          model = config.fetch(:model)
          bounds[key] = if config.fetch(:strategy) != :soft_delete
            0
          else
            scope = model.unscoped
              .where(user_id: user.id)
              .where.not(deleted_at: nil)
            scope = scope.where.not(floor_number: 1) if model == Community::Post
            scope.where.not(
              id: DataGovernance::ContentLifecycleRecord
                .where(target_type: model.base_class.name)
                .select(:target_id)
            )
              .maximum(:id).to_i
          end
        end
      end

      def historical_deletion_sql
        count_expressions = AuthoredContentDeletion::RESOURCE_KEYS.map do |key|
          path = "{identity.authored_content,details,deleted_records,#{key}}"
          value = "account_closure_results #>> '#{path}'"
          "CASE WHEN (#{value}) ~ '^[0-9]+$' THEN (#{value})::bigint ELSE 0 END"
        end
        [
          "account_closure_outcome IN (?) OR " \
            "account_closure_results #>> " \
            "'{identity.authored_content,details,closure_mode}' = 'delete_content' OR " \
            "account_closure_results #>> " \
            "'{identity.authored_content,details,outcome}' IN (?) OR " \
            "(#{count_expressions.join(' + ')}) > 0",
          DELETE_CONTENT_OUTCOMES,
          DELETE_CONTENT_OUTCOMES
        ]
      end

      def missing_lifecycle_sql
        connection = ApplicationRecord.connection
        lifecycle_table = connection.quote_table_name(
          DataGovernance::ContentLifecycleRecord.table_name
        )
        user_table = connection.quote_table_name(User.table_name)
        clauses = AuthoredContentContributor::RESOURCE_CONFIG.values
          .select { |config| config.fetch(:strategy) == :soft_delete }
          .map do |config|
          model = config.fetch(:model)
          content_table = connection.quote_table_name(model.table_name)
          target_type = connection.quote(model.base_class.name)
          structural_filter = model == Community::Post ? "AND account_closure_content.floor_number <> 1" : ""
          <<~SQL.squish
            EXISTS (
              SELECT 1
              FROM #{content_table} account_closure_content
              WHERE account_closure_content.user_id = #{user_table}.id
                AND account_closure_content.deleted_at IS NOT NULL
                #{structural_filter}
                AND NOT EXISTS (
                  SELECT 1
                  FROM #{lifecycle_table} account_closure_lifecycle
                  WHERE account_closure_lifecycle.target_type = #{target_type}
                    AND account_closure_lifecycle.target_id = account_closure_content.id
                )
            )
          SQL
        end
        clauses.map { |clause| "(#{clause})" }.join(" OR ")
      end

      def active_authored_content_sql
        connection = ApplicationRecord.connection
        user_table = connection.quote_table_name(User.table_name)
        clauses = AuthoredContentContributor::RESOURCE_CONFIG.values
          .select { |config| config.fetch(:strategy) == :soft_delete }
          .map do |config|
          model = config.fetch(:model)
          content_table = connection.quote_table_name(model.table_name)
          structural_filter = model == Community::Post ? "AND retained_account_closure_content.floor_number <> 1" : ""
          <<~SQL.squish
            EXISTS (
              SELECT 1
              FROM #{content_table} retained_account_closure_content
              WHERE retained_account_closure_content.user_id = #{user_table}.id
                AND retained_account_closure_content.deleted_at IS NULL
                #{structural_filter}
            )
          SQL
        end
        clauses.map { |clause| "(#{clause})" }.join(" OR ")
      end

      def topic_scrub_required_sql
        connection = ApplicationRecord.connection
        marker = "account_closure_results #>> " \
          "'{identity.authored_content,details,topic_titles_scrubbed}'"
        topic_table = connection.quote_table_name(Community::Topic.table_name)
        lifecycle_table = connection.quote_table_name(
          DataGovernance::ContentLifecycleRecord.table_name
        )
        user_table = connection.quote_table_name(User.table_name)
        replacement_sql = structural_tombstone_sql("mcweb.identity.deleted_content_title")
        target_type = connection.quote(Community::Topic.base_class.name)
        deletion_reason = connection.quote("account_closure_delete_content")
        restored = connection.quote("restored")
        <<~SQL.squish
          EXISTS (
            SELECT 1
            FROM #{topic_table} account_closure_topic_titles
            WHERE account_closure_topic_titles.user_id = #{user_table}.id
              AND (
                COALESCE((#{marker}), 'false') <> 'true'
                OR account_closure_topic_titles.deleted_at IS NOT NULL
                OR account_closure_topic_titles.title NOT IN (#{replacement_sql})
                OR EXISTS (
                  SELECT 1
                  FROM #{lifecycle_table} account_closure_topic_lifecycle
                  WHERE account_closure_topic_lifecycle.target_type = #{target_type}
                    AND account_closure_topic_lifecycle.target_id = account_closure_topic_titles.id
                    AND account_closure_topic_lifecycle.deletion_reason = #{deletion_reason}
                    AND (
                      account_closure_topic_lifecycle.status <> #{restored}
                      OR account_closure_topic_lifecycle.target_snapshot ? 'label'
                      OR account_closure_topic_lifecycle.target_snapshot #>>
                        '{owner,username}' IS NOT NULL
                    )
                )
              )
          )
        SQL
      end


      def opening_post_scrub_required_sql
        connection = ApplicationRecord.connection
        marker = "account_closure_results #>> " \
          "'{identity.authored_content,details,opening_posts_scrubbed}'"
        post_table = connection.quote_table_name(Community::Post.table_name)
        edit_table = connection.quote_table_name(Community::PostEdit.table_name)
        attachment_table = connection.quote_table_name(Community::PostAttachment.table_name)
        upload_table = connection.quote_table_name(Community::Upload.table_name)
        lifecycle_table = connection.quote_table_name(
          DataGovernance::ContentLifecycleRecord.table_name
        )
        user_table = connection.quote_table_name(User.table_name)
        replacement_sql = structural_tombstone_sql("mcweb.identity.deleted_content_body")
        target_type = connection.quote(Community::Post.base_class.name)
        deletion_reason = connection.quote("account_closure_delete_content")
        restored = connection.quote("restored")
        upload_kinds = %w[inline_image post_attachment].map { |kind| connection.quote(kind) }.join(", ")
        <<~SQL.squish
          EXISTS (
            SELECT 1
            FROM #{post_table} account_closure_opening_posts
            WHERE account_closure_opening_posts.user_id = #{user_table}.id
              AND account_closure_opening_posts.floor_number = 1
              AND (
                COALESCE((#{marker}), 'false') <> 'true'
                OR account_closure_opening_posts.deleted_at IS NOT NULL
                OR account_closure_opening_posts.body NOT IN (#{replacement_sql})
                OR EXISTS (
                  SELECT 1
                  FROM #{edit_table} account_closure_opening_post_edits
                  WHERE account_closure_opening_post_edits.forum_post_id = account_closure_opening_posts.id
                    AND (
                      COALESCE(account_closure_opening_post_edits.body_before, '') NOT IN (#{replacement_sql})
                      OR COALESCE(account_closure_opening_post_edits.body_after, '') NOT IN (#{replacement_sql})
                      OR account_closure_opening_post_edits.reason IS NOT NULL
                    )
                )
                OR EXISTS (
                  SELECT 1
                  FROM #{attachment_table} account_closure_opening_post_attachments
                  WHERE account_closure_opening_post_attachments.forum_post_id = account_closure_opening_posts.id
                )
                OR EXISTS (
                  SELECT 1
                  FROM #{upload_table} account_closure_opening_post_uploads
                  WHERE account_closure_opening_post_uploads.forum_post_id = account_closure_opening_posts.id
                    AND account_closure_opening_post_uploads.kind IN (#{upload_kinds})
                )
                OR EXISTS (
                  SELECT 1
                  FROM #{lifecycle_table} account_closure_opening_post_lifecycle
                  WHERE account_closure_opening_post_lifecycle.target_type = #{target_type}
                    AND account_closure_opening_post_lifecycle.target_id = account_closure_opening_posts.id
                    AND account_closure_opening_post_lifecycle.deletion_reason = #{deletion_reason}
                    AND (
                      account_closure_opening_post_lifecycle.status <> #{restored}
                      OR account_closure_opening_post_lifecycle.target_snapshot ? 'label'
                      OR account_closure_opening_post_lifecycle.target_snapshot #>>
                        '{owner,username}' IS NOT NULL
                    )
                )
              )
          )
        SQL
      end

      def profile_post_scrub_required_sql
        connection = ApplicationRecord.connection
        marker = "account_closure_results #>> " \
          "'{identity.authored_content,details,profile_posts_scrubbed}'"
        post_table = connection.quote_table_name(Community::ProfilePost.table_name)
        lifecycle_table = connection.quote_table_name(
          DataGovernance::ContentLifecycleRecord.table_name
        )
        user_table = connection.quote_table_name(User.table_name)
        replacement_sql = structural_tombstone_sql("mcweb.identity.deleted_content_body")
        target_type = connection.quote(Community::ProfilePost.base_class.name)
        deletion_reason = connection.quote("account_closure_delete_content")
        restored = connection.quote("restored")
        <<~SQL.squish
          EXISTS (
            SELECT 1
            FROM #{post_table} account_closure_profile_posts
            WHERE account_closure_profile_posts.user_id = #{user_table}.id
              AND (
                COALESCE((#{marker}), 'false') <> 'true'
                OR account_closure_profile_posts.deleted_at IS NOT NULL
                OR account_closure_profile_posts.body NOT IN (#{replacement_sql})
                OR EXISTS (
                  SELECT 1
                  FROM #{lifecycle_table} account_closure_profile_post_lifecycle
                  WHERE account_closure_profile_post_lifecycle.target_type = #{target_type}
                    AND account_closure_profile_post_lifecycle.target_id = account_closure_profile_posts.id
                    AND account_closure_profile_post_lifecycle.deletion_reason = #{deletion_reason}
                    AND (
                      account_closure_profile_post_lifecycle.status <> #{restored}
                      OR account_closure_profile_post_lifecycle.target_snapshot ? 'label'
                      OR account_closure_profile_post_lifecycle.target_snapshot #>>
                        '{owner,username}' IS NOT NULL
                    )
                )
              )
          )
        SQL
      end

      def structural_tombstone_sql(key)
        connection = ApplicationRecord.connection
        values = I18n.available_locales.map do |locale|
          I18n.t(key, locale:)
        end.uniq
        values = [ I18n.t(key) ] if values.empty?
        values.map { |value| connection.quote(value) }.join(", ")
      end

      def normalized_existing_counts(value)
        source = value.to_h.deep_stringify_keys
        AuthoredContentDeletion::RESOURCE_KEYS.index_with do |key|
          source.fetch(key, 0).to_i
        end
      end

      def recheck_due?(value)
        return true if value.blank?

        Time.iso8601(value.to_s) <= @at
      rescue ArgumentError
        true
      end
    end
  end
end
