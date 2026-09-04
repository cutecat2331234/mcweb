# frozen_string_literal: true

module Identity
  module AccountClosure
    module AuthoredContentDeletion
      HANDLER_KEY = "identity.account_closure_authored_content_deletion"
      SCHEMA_VERSION = 2
      BATCH_SIZE = 50
      RESOURCE_KEYS = AuthoredContentContributor::RESOURCE_CONFIG.keys.freeze
      REQUEST_KEY_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i
      ACTIVE_STATUSES = %w[queued processing].freeze
      WAITING_STATUS = "waiting_for_blockers"
      RECOVERY_BACKOFF_STATUS = "recovery_backoff"
      MANUAL_ATTENTION_STATUS = "manual_attention"
      STRUCTURAL_RESTORATION_REASON =
        "account_closure_structural_container_preserved"
      NON_TERMINAL_STATUSES = (
        ACTIVE_STATUSES + [ WAITING_STATUS, RECOVERY_BACKOFF_STATUS ]
      ).freeze
      BLOCKER_RECHECK_DELAYS = [ 1.hour, 6.hours, 24.hours ].freeze

      class ProcessingError < StandardError; end

      module_function

      def register(registry)
        registry.register(
          key: HANDLER_KEY,
          source_kind: "user",
          queue: "maintenance",
          replay_contract: "idempotent",
          lease: 15.minutes,
          heartbeat: 1.minute,
          max_attempts: 10,
          retry_delays: [
            1.minute,
            5.minutes,
            15.minutes,
            30.minutes,
            1.hour,
            2.hours,
            4.hours,
            8.hours,
            12.hours
          ],
          argument_schema: {
            "request_key" => {
              type: "string",
              required: true,
              maximum: 36,
              pattern: REQUEST_KEY_PATTERN
            },
            "batch_number" => {
              type: "integer",
              required: true,
              minimum: 1
            }
          }
        ) do |intent, context|
          execute(intent, context:)
        end
      end

      def enqueue_initial!(user:, contribution:, requested_at:)
        details = contribution.to_h.deep_stringify_keys.fetch("details", {})
        processing = details.fetch("processing", {}).to_h
        return unless processing.fetch("status", nil).in?(ACTIVE_STATUSES)

        record_batch!(
          user:,
          request_key: processing.fetch("request_key"),
          batch_number: processing.fetch("batch_number", 1),
          requested_at:
        )
      end

      def execute(intent, context: nil)
        user = User.find_by(id: intent.source_id)
        return skipped("source_missing") unless user

        request_key = intent.arguments.fetch("request_key")
        batch_number = intent.arguments.fetch("batch_number").to_i
        request_state = active_request_state(user, request_key, batch_number:)
        return skipped(request_state) unless request_state == "active"

        if account_hold_blocks_request?(user, request_key:)
          defer_for_blockers!(
            user:,
            request_key:,
            batch_number:,
            blockers: [ "legal_hold" ],
            retained_records: empty_counts,
            global: true
          )
          return Operations::DurableEnqueueResult.succeeded(
            metadata: { processed_records: 0, deferred_for_blockers: true }
          )
        end

        processed = 0
        while processed < BATCH_SIZE
          work_item = next_work_item(user, request_key, batch_number:)
          break unless work_item

          item_outcome = process_one!(
            user:,
            request_key:,
            batch_number:,
            resource_key: work_item.fetch(:resource_key),
            target_id: work_item.fetch(:target_id)
          )
          break if item_outcome == :superseded

          processed += 1 if item_outcome == :processed
        end

        request_state = active_request_state(user, request_key, batch_number:)
        if request_state != "active"
          return Operations::DurableEnqueueResult.succeeded(
            metadata: {
              processed_records: processed,
              superseded: true,
              superseded_reason: request_state
            }
          )
        end

        if next_work_item(user, request_key, batch_number:)
          schedule_next_batch!(user:, request_key:, completed_batch_number: batch_number)
        else
          finalize!(user:, request_key:, batch_number:)
        end

        Operations::DurableEnqueueResult.succeeded(
          metadata: { processed_records: processed }
        )
      rescue Operations::DurableEnqueueAdmission::Unavailable
        raise Operations::DurableEnqueueCatalog::ExecutionError,
              Operations::DurableEnqueueAdmission::ERROR_CODE
      rescue ProcessingError, ActiveRecord::ActiveRecordError => error
        raise Operations::DurableEnqueueCatalog::ExecutionError.new(
          "account_closure_authored_content_processing_failed",
          error.class.name
        )
      end

      def record_batch!(user:, request_key:, batch_number:, requested_at: Time.current)
        Operations::DurableEnqueueAdmission.record!(
          handler: HANDLER_KEY,
          source_id: user.id,
          dedupe_key: "account-closure-content:#{user.id}:#{request_key}:#{batch_number}",
          arguments: {
            request_key:,
            batch_number:
          },
          requested_at:
        )
      end

      def processing_for(user)
        user.account_closure_results
          .to_h
          .dig("identity.authored_content", "details", "processing")
          .to_h
          .deep_stringify_keys
      end

      def active_request_state(user, request_key, batch_number:)
        processing = processing_for(user.reload)
        return "closure_request_inactive" unless processing.fetch("request_key", nil) == request_key
        return "closure_request_inactive" unless processing.fetch("status", nil).in?(ACTIVE_STATUSES)
        return "batch_superseded" if processing.fetch("batch_number", 0).to_i > batch_number
        return "batch_not_current" if processing.fetch("batch_number", 0).to_i < batch_number

        "active"
      end

      def next_work_item(user, request_key, batch_number:)
        loop do
          processing = processing_for(user.reload)
          return unless processing.fetch("request_key", nil) == request_key
          return unless processing.fetch("status", nil).in?(ACTIVE_STATUSES)
          return unless processing.fetch("batch_number", 0).to_i == batch_number

          resource_index = processing.fetch("resource_index", 0).to_i
          return if resource_index >= RESOURCE_KEYS.length

          resource_key = RESOURCE_KEYS.fetch(resource_index)
          cursor = processing.fetch("cursors", {}).fetch(resource_key, 0).to_i
          upper_bound = processing.fetch("upper_bounds", {}).fetch(resource_key, 0).to_i
          target_id = candidate_scope(
            user:,
            resource_key:,
            repair_only: processing.fetch("repair_only", false)
          ).where(id: (cursor + 1)..upper_bound).order(:id).limit(1).pick(:id)
          return { resource_key:, target_id: } if target_id

          advance_resource!(
            user:,
            request_key:,
            resource_key:,
            upper_bound:,
            expected_index: resource_index,
            batch_number:
          )
        end
      end

      def process_one!(user:, request_key:, batch_number:, resource_key:, target_id:)
        outcome = :processed
        cleanup_upload_ids = []
        User.transaction(requires_new: true) do
          locked_user = User.lock.find(user.id)
          unless active_processing?(locked_user, request_key:, batch_number:)
            outcome = :superseded
            next
          end

          results, details, processing = mutable_processing(
            locked_user,
            request_key:,
            batch_number:
          )
          cursor = processing.fetch("cursors", {}).fetch(resource_key, 0).to_i
          if cursor >= target_id
            outcome = :skipped
            next
          end

          target = resource_model(resource_key).unscoped
            .where(user_id: locked_user.id, id: target_id)
            .lock
            .first
          unless target
            increment_resource_count!(processing, "missing_records", resource_key)
            update_cursor!(processing, resource_key, target_id)
            persist_progress!(locked_user, results:, details:, processing:)
            next
          end

          if processing.fetch("repair_only", false) &&
              (!target.soft_deleted? || lifecycle_exists?(target))
            update_cursor!(processing, resource_key, target_id)
            persist_progress!(locked_user, results:, details:, processing:)
            next
          end

          policy = DataGovernance::DeletionPolicy.call(target:)
          raise ProcessingError, "deletion_policy_failed" unless policy.success?

          blockers = Array(policy.value.fetch(:blockers)).map(&:to_s).uniq.sort
          retention_policy = policy.value.fetch(:policy, nil)
          raise ProcessingError, "retention_policy_missing" unless retention_policy
          blockers << "content_not_deletable" unless retention_policy.fetch(:user_deletable)
          blockers.uniq!
          blockers.sort!
          repair_only = processing.fetch("repair_only", false)
          if blockers.any? && !repair_only
            increment_resource_count!(processing, "retained_records", resource_key)
            blockers.each { |code| increment_blocker_count!(processing, code) }
          else
            target_cleanup_ids = process_target!(
              target:,
              actor: locked_user,
              resource_key:,
              request_key:,
              target_id:,
              repair_only:,
              blockers:
            )
            cleanup_upload_ids.concat(Array(target_cleanup_ids))
            blockers.each { |code| increment_blocker_count!(processing, code) } if repair_only
            increment_resource_count!(processing, "deleted_records", resource_key)
          end

          update_cursor!(processing, resource_key, target_id)
          persist_progress!(locked_user, results:, details:, processing:)
        end
        if outcome == :processed && cleanup_upload_ids.any?
          scheduled_upload_ids = cleanup_upload_ids.uniq.freeze
          ActiveRecord.after_all_transactions_commit do
            DataGovernance::ContentRegistry.enqueue_scheduled_upload_cleanup(
              scheduled_upload_ids
            )
          end
        end
        outcome
      end

      def advance_resource!(
        user:,
        request_key:,
        resource_key:,
        upper_bound:,
        expected_index:,
        batch_number:
      )
        user.with_lock do
          return unless active_processing?(user, request_key:, batch_number:)

          results, details, processing = mutable_processing(
            user,
            request_key:,
            batch_number:
          )
          return unless processing.fetch("resource_index", 0).to_i == expected_index

          update_cursor!(processing, resource_key, upper_bound)
          processing["resource_index"] = expected_index + 1
          persist_progress!(user, results:, details:, processing:)
        end
      end

      def schedule_next_batch!(user:, request_key:, completed_batch_number:)
        user.with_lock do
          results, details, processing = mutable_processing(user, request_key:)
          current_batch = processing.fetch("batch_number", 1).to_i
          return if current_batch > completed_batch_number

          next_batch = current_batch + 1
          processing["batch_number"] = next_batch
          processing["status"] = "queued"
          processing["updated_at"] = Time.current.iso8601
          persist_progress!(
            user,
            results:,
            details:,
            processing:,
            mark_processing: false
          )
          record_batch!(
            user:,
            request_key:,
            batch_number: next_batch,
            requested_at: Time.current
          )
        end
      end

      def finalize!(user:, request_key:, batch_number:)
        user.with_lock do
          return unless active_processing?(user, request_key:, batch_number:)

          results, details, processing = mutable_processing(
            user,
            request_key:,
            batch_number:
          )

          deleted_records = normalized_counts(processing.fetch("deleted_records", {}))
          retained_records = normalized_counts(processing.fetch("retained_records", {}))
          missing_records = normalized_counts(processing.fetch("missing_records", {}))
          if !processing.fetch("repair_only", false) && retained_records.values.sum.positive?
            defer_locked_for_blockers!(
              user:,
              results:,
              details:,
              processing:,
              request_key:,
              retained_records:,
              blockers: processing.fetch("blocker_counts", {}).to_h.keys,
              global: false
            )
            next
          end

          outcome = completion_outcome(processing:)
          completed_at = Time.current
          processing.merge!(
            "status" => "completed",
            "resource_index" => RESOURCE_KEYS.length,
            "completed_at" => completed_at.iso8601,
            "updated_at" => completed_at.iso8601
          )
          if processing.fetch("repair_only", false)
            details.merge!(
              "outcome" => outcome,
              "lifecycle_repaired_records" => deleted_records,
              "lifecycle_reconciliation_missing_records" => missing_records,
              "lifecycle_reconciliation_blocker_counts" =>
                processing.fetch("blocker_counts", {}).to_h
            )
          else
            details.merge!(
              "outcome" => outcome,
              "closure_mode" => "delete_content",
              "topic_titles_scrubbed" => true,
              "opening_posts_scrubbed" => true,
              "profile_posts_scrubbed" => true,
              "deleted_records" => deleted_records,
              "retained_records" => retained_records,
              "missing_records" => missing_records,
              "blocker_counts" => processing.fetch("blocker_counts", {}).to_h
            )
          end
          details["processing"] = processing
          results.fetch("identity.authored_content")["details"] = details
          user.update!(
            account_closure_outcome: outcome,
            account_closure_results: results
          )

          audit = Administration::AuditLogger.call(
            actor: user,
            action: "identity.account_closure_content_completed",
            resource: user,
            request_id: request_key,
            reason: "account_closure_delete_content",
            metadata: {
              repair_only: processing.fetch("repair_only", false),
              deleted_records:,
              retained_records:,
              missing_records:,
              blocker_counts: processing.fetch("blocker_counts", {}).to_h,
              lifecycle_schema_version: SCHEMA_VERSION
            },
            before_state: {
              outcome: processing.fetch(
                "prior_outcome",
                "authored_content_deletion_queued"
              )
            },
            after_state: { outcome:, processing_status: "completed" }
          )
          raise ProcessingError, "completion_audit_failed" unless audit.success?
        end
      end

      def mutable_processing(user, request_key:, batch_number: nil)
        results = user.account_closure_results.to_h.deep_stringify_keys.deep_dup
        contribution = results.fetch("identity.authored_content")
        details = contribution.fetch("details").to_h
        processing = details.fetch("processing").to_h
        unless processing.fetch("request_key", nil) == request_key &&
            processing.fetch("status", nil).in?(ACTIVE_STATUSES) &&
            (batch_number.nil? || processing.fetch("batch_number", 0).to_i == batch_number)
          raise ProcessingError, "closure_request_inactive"
        end

        [ results, details, processing ]
      end

      def active_processing?(user, request_key:, batch_number: nil)
        processing = processing_for(user)
        processing.fetch("request_key", nil) == request_key &&
          processing.fetch("status", nil).in?(ACTIVE_STATUSES) &&
          (batch_number.nil? || processing.fetch("batch_number", 0).to_i == batch_number)
      end

      def persist_progress!(user, results:, details:, processing:, mark_processing: true)
        if mark_processing && processing["status"] != "completed"
          processing["status"] = "processing"
        end
        processing["updated_at"] = Time.current.iso8601
        details["processing"] = processing
        results.fetch("identity.authored_content")["details"] = details
        user.update!(account_closure_results: results)
      end

      def candidate_scope(user:, resource_key:, repair_only:)
        model = resource_model(resource_key)
        scope = model.unscoped.where(user_id: user.id)
        return scope.none if repair_only && resource_strategy(resource_key) != :soft_delete
        return scope if resource_strategy(resource_key).in?([ :scrub_title, :scrub_body ])
        if resource_key == "posts"
          return scope.where.not(floor_number: 1) if repair_only

          return scope.where("deleted_at IS NULL OR floor_number = 1")
        end
        return scope.where(deleted_at: nil) unless repair_only

        scope.where.not(deleted_at: nil).where.not(
          id: DataGovernance::ContentLifecycleRecord
            .where(target_type: model.base_class.name)
            .select(:target_id)
        )
      end

      def account_hold_blocks_request?(user, request_key:)
        processing = processing_for(user.reload)
        return false unless processing.fetch("request_key", nil) == request_key
        return false if processing.fetch("repair_only", false)

        DataGovernance::RetentionHold.effective.exists?(target: user)
      end

      def resource_model(resource_key)
        AuthoredContentContributor::RESOURCE_CONFIG.fetch(resource_key).fetch(:model)
      end

      def resource_strategy(resource_key)
        AuthoredContentContributor::RESOURCE_CONFIG.fetch(resource_key).fetch(:strategy)
      end

      def process_target!(
        target:,
        actor:,
        resource_key:,
        request_key:,
        target_id:,
        repair_only:,
        blockers:
      )
        if resource_strategy(resource_key) == :scrub_title
          raise ProcessingError, "topic_lifecycle_repair_unsupported" if repair_only

          scrub_topic_title!(
            topic: target,
            actor:,
            request_id: per_record_request_id(request_key, resource_key, target_id)
          )
          return []
        end

        if resource_strategy(resource_key) == :scrub_body
          raise ProcessingError, "shared_body_lifecycle_repair_unsupported" if repair_only

          scrub_shared_body!(
            target:,
            actor:,
            request_id: per_record_request_id(request_key, resource_key, target_id)
          )
          return []
        end

        if resource_key == "posts" && structural_opening_post?(target)
          raise ProcessingError, "opening_post_lifecycle_repair_unsupported" if repair_only

          return scrub_opening_post!(
            post: target,
            actor:,
            request_id: per_record_request_id(request_key, resource_key, target_id)
          )
        end

        lifecycle_at = repair_only ? target.deleted_at : Time.current
        deleted = DataGovernance::SoftDeleteContent.call(
          target:,
          actor:,
          reason: "account_closure_delete_content",
          request_id: per_record_request_id(request_key, resource_key, target_id),
          at: lifecycle_at,
          reconcile_existing: repair_only
        )
        unless deleted.success?
          raise ProcessingError,
                deleted.code.presence || "soft_delete_content_failed"
        end
        return [] unless repair_only && blockers.any?

        deleted.value.fetch(:record).update!(
          blocker_codes: blockers,
          last_evaluated_at: Time.current
        )
        []
      end

      def scrub_topic_title!(topic:, actor:, request_id:)
        neutralize_structural_lifecycle!(
          target: topic,
          actor:,
          request_id: Digest::SHA256.hexdigest("#{request_id}:neutralize").first(64)
        )
        replacement = I18n.t("mcweb.identity.deleted_content_title", locale: actor.locale)
        before_title = topic.title
        replayed = before_title == replacement
        topic.update!(title: replacement) unless replayed

        return if replayed

        audit = Administration::AuditLogger.call(
          actor:,
          action: "identity.account_closure_topic_title_scrubbed",
          resource: topic,
          request_id:,
          reason: "account_closure_delete_content",
          before_state: { title_sha256: Digest::SHA256.hexdigest(before_title.to_s) },
          after_state: { title_scrubbed: true },
          metadata: { preserves_topic_container: true }
        )
        raise ProcessingError, "topic_title_scrub_audit_failed" unless audit.success?
      end

      def structural_opening_post?(post)
        post.is_a?(Community::Post) && post.floor_number == 1
      end

      def scrub_shared_body!(target:, actor:, request_id:)
        neutralize_structural_lifecycle!(
          target:,
          actor:,
          request_id: Digest::SHA256.hexdigest("#{request_id}:neutralize").first(64)
        )
        replacement = I18n.t("mcweb.identity.deleted_content_body", locale: actor.locale)
        before_body = target.body
        replayed = before_body == replacement
        unless replayed
          target.update!(
            body: replacement,
            edited_at: Time.current,
            revision: target.revision + 1
          )
        end
        return if replayed

        audit = Administration::AuditLogger.call(
          actor:,
          action: "identity.account_closure_shared_body_scrubbed",
          resource: target,
          request_id:,
          reason: "account_closure_delete_content",
          before_state: { body_sha256: Digest::SHA256.hexdigest(before_body.to_s) },
          after_state: { body_scrubbed: true },
          metadata: { preserves_shared_container: true }
        )
        raise ProcessingError, "shared_body_scrub_audit_failed" unless audit.success?
      end

      def scrub_opening_post!(post:, actor:, request_id:)
        neutralize_structural_lifecycle!(
          target: post,
          actor:,
          request_id: Digest::SHA256.hexdigest("#{request_id}:neutralize").first(64)
        )
        replacement = I18n.t("mcweb.identity.deleted_content_body", locale: actor.locale)
        before_body = post.body
        now = Time.current
        replayed = before_body == replacement &&
          post.edits.where(
            "body_before IS NULL OR body_before <> :replacement OR " \
            "body_after IS NULL OR body_after <> :replacement OR " \
            "reason IS NOT NULL",
            replacement:
          ).none? &&
          Community::PostAttachment.with_discarded.where(forum_post_id: post.id).none? &&
          Community::Upload
            .where(kind: %w[inline_image post_attachment], forum_post_id: post.id)
            .none?
        return [] if replayed

        cleanup_upload_ids = DataGovernance::ContentRegistry
          .schedule_post_upload_cleanup(post_ids: [ post.id ], at: now, detach: true)
        post.update!(
          body: replacement,
          edited_at: now,
          revision: post.revision + 1
        )
        post.edits.update_all(
          body_before: replacement,
          body_after: replacement,
          reason: nil,
          updated_at: now
        )

        audit = Administration::AuditLogger.call(
          actor:,
          action: "identity.account_closure_opening_post_scrubbed",
          resource: post,
          request_id:,
          reason: "account_closure_delete_content",
          before_state: { body_sha256: Digest::SHA256.hexdigest(before_body.to_s) },
          after_state: {
            body_scrubbed: true,
            edit_history_scrubbed: true,
            uploads_scheduled_for_cleanup: cleanup_upload_ids.size
          },
          metadata: {
            preserves_topic_structure: true,
            attachments_detached: true
          }
        )
        raise ProcessingError, "opening_post_scrub_audit_failed" unless audit.success?

        cleanup_upload_ids
      end

      def neutralize_structural_lifecycle!(target:, actor:, request_id:)
        lifecycle = DataGovernance::ContentLifecycleRecord.lock.find_by(
          target_type: target.class.base_class.name,
          target_id: target.id,
          deletion_reason: "account_closure_delete_content"
        )
        return unless lifecycle
        if lifecycle.status_purged?
          raise ProcessingError, "structural_lifecycle_purged_with_existing_target"
        end

        scrubbed_snapshot = DataGovernance::ContentRegistry.scrubbed_snapshot(
          lifecycle.target_snapshot,
          type: target.class.base_class.name
        )
        snapshot_scrubbed = lifecycle.target_snapshot.deep_stringify_keys !=
          scrubbed_snapshot.deep_stringify_keys
        restoration_reason_normalized =
          lifecycle.restoration_reason != STRUCTURAL_RESTORATION_REASON
        target_was_deleted = target.soft_deleted?
        target.restore! if target_was_deleted
        if lifecycle.status_restored?
          if snapshot_scrubbed || restoration_reason_normalized
            lifecycle.update!(
              target_snapshot: scrubbed_snapshot,
              restoration_reason: STRUCTURAL_RESTORATION_REASON
            )
          end
          DataGovernance::ContentRegistry.after_lifecycle_change(target) if target_was_deleted
          audit_structural_snapshot_scrub!(
            target:,
            actor:,
            request_id:,
            lifecycle:
          ) if snapshot_scrubbed
          return
        end

        now = Time.current
        lifecycle.update!(
          status: "restored",
          restored_by: nil,
          restored_at: now,
          restoration_reason: STRUCTURAL_RESTORATION_REASON,
          target_snapshot: scrubbed_snapshot,
          blocker_codes: [],
          last_evaluated_at: now
        )
        DataGovernance::ContentRegistry.after_lifecycle_change(target)
        audit = Administration::AuditLogger.call(
          actor:,
          action: "identity.account_closure_structural_lifecycle_neutralized",
          resource: target,
          request_id:,
          reason: STRUCTURAL_RESTORATION_REASON,
          metadata: {
            lifecycle_public_id: lifecycle.public_id,
            target_type: target.class.base_class.name,
            lifecycle_snapshot_scrubbed: snapshot_scrubbed
          }
        )
        raise ProcessingError, "structural_lifecycle_neutralize_audit_failed" unless audit.success?
      end

      def audit_structural_snapshot_scrub!(target:, actor:, request_id:, lifecycle:)
        audit = Administration::AuditLogger.call(
          actor:,
          action: "identity.account_closure_structural_lifecycle_snapshot_scrubbed",
          resource: target,
          request_id: Digest::SHA256.hexdigest("#{request_id}:snapshot").first(64),
          reason: STRUCTURAL_RESTORATION_REASON,
          before_state: { lifecycle_snapshot_contained_label: true },
          after_state: { lifecycle_snapshot_scrubbed: true },
          metadata: {
            lifecycle_public_id: lifecycle.public_id,
            target_type: target.class.base_class.name
          }
        )
        raise ProcessingError, "structural_lifecycle_snapshot_scrub_audit_failed" unless audit.success?
      end

      def lifecycle_exists?(target)
        DataGovernance::ContentLifecycleRecord.exists?(
          target_type: target.class.base_class.name,
          target_id: target.id
        )
      end

      def update_cursor!(processing, resource_key, target_id)
        processing["cursors"] = normalized_counts(processing.fetch("cursors", {}))
        processing["cursors"][resource_key] = target_id.to_i
      end

      def increment_resource_count!(processing, count_key, resource_key)
        processing[count_key] = normalized_counts(processing.fetch(count_key, {}))
        processing[count_key][resource_key] += 1
      end

      def increment_blocker_count!(processing, code)
        processing["blocker_counts"] = processing.fetch("blocker_counts", {}).to_h.deep_stringify_keys
        processing["blocker_counts"][code] = processing["blocker_counts"].fetch(code, 0).to_i + 1
      end

      def normalized_counts(value)
        source = value.to_h.deep_stringify_keys
        RESOURCE_KEYS.index_with { |key| source.fetch(key, 0).to_i }
      end

      def completion_outcome(processing:)
        if processing.fetch("repair_only", false)
          processing.fetch("prior_outcome", "authored_content_deleted")
        else
          "authored_content_deleted"
        end
      end

      def defer_for_blockers!(
        user:,
        request_key:,
        batch_number:,
        blockers:,
        retained_records:,
        global:
      )
        user.with_lock do
          return unless active_processing?(user, request_key:, batch_number:)

          results, details, processing = mutable_processing(
            user,
            request_key:,
            batch_number:
          )
          defer_locked_for_blockers!(
            user:,
            results:,
            details:,
            processing:,
            request_key:,
            blockers:,
            retained_records:,
            global:
          )
        end
      end

      def defer_locked_for_blockers!(
        user:,
        results:,
        details:,
        processing:,
        request_key:,
        blockers:,
        retained_records:,
        global:
      )
        now = Time.current
        normalized_blockers = Array(blockers).map(&:to_s).reject(&:blank?).uniq.sort
        recheck_count = processing.fetch("blocker_recheck_count", 0).to_i
        next_recheck_at = now + blocker_recheck_delay(recheck_count)
        prior_status = processing.fetch("status", "processing")
        processing.merge!(
          "status" => WAITING_STATUS,
          "next_recheck_at" => next_recheck_at.iso8601,
          "last_deferred_at" => now.iso8601,
          "last_blockers" => normalized_blockers,
          "global_blocker" => global,
          "updated_at" => now.iso8601
        )
        processing["retained_records"] = normalized_counts(retained_records)
        if global
          processing["blocker_counts"] = normalized_blockers.index_with { 1 }
        end
        details.merge!(
          "outcome" => "legally_retained",
          "retained_records" => normalized_counts(retained_records),
          "blocker_counts" => processing.fetch("blocker_counts", {}).to_h,
          "processing" => processing
        )
        results.fetch("identity.authored_content")["details"] = details
        user.update!(
          account_closure_outcome: "legally_retained",
          account_closure_results: results
        )

        audit = Administration::AuditLogger.call(
          actor: user,
          action: "identity.account_closure_content_deferred",
          resource: user,
          request_id: deferred_audit_request_id(
            request_key,
            processing.fetch("batch_number", 1)
          ),
          reason: "account_closure_content_blocked",
          metadata: {
            global_blocker: global,
            blockers: normalized_blockers,
            retained_records: normalized_counts(retained_records),
            next_recheck_at: next_recheck_at.iso8601,
            lifecycle_schema_version: SCHEMA_VERSION
          },
          before_state: { processing_status: prior_status },
          after_state: {
            outcome: "legally_retained",
            processing_status: WAITING_STATUS
          }
        )
        raise ProcessingError, "deferred_audit_failed" unless audit.success?
      end

      def blocker_recheck_delay(recheck_count)
        BLOCKER_RECHECK_DELAYS.fetch(
          [ recheck_count, BLOCKER_RECHECK_DELAYS.length - 1 ].min
        )
      end

      def deferred_audit_request_id(request_key, batch_number)
        Digest::SHA256.hexdigest(
          "#{request_key}:deferred:#{batch_number}"
        ).first(64)
      end

      def empty_counts
        RESOURCE_KEYS.index_with { 0 }
      end

      def per_record_request_id(request_key, resource_key, target_id)
        Digest::SHA256.hexdigest(
          "#{request_key}:#{resource_key}:#{target_id}"
        ).first(64)
      end

      def skipped(code)
        Operations::DurableEnqueueResult.skipped(error_code: code)
      end
    end
  end
end
