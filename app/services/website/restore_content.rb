# frozen_string_literal: true

module Website
  class RestoreContent < ApplicationService
    include LifecycleContract

    def initialize(content:, actor:, reason:, confirmation:, expected_lock_version:, idempotency_key:)
      @content = content
      @actor = actor
      @reason = reason
      @confirmation = confirmation.to_s
      @expected_lock_version = expected_lock_version
      @idempotency_key = idempotency_key
    end

    def call
      reason = normalize_reason!(@reason)
      key = normalize_idempotency_key!(@idempotency_key)
      digest = idempotency_digest(key)
      expected = expected_version!(@expected_lock_version)
      request_operation_digest = operation_digest(
        event: "restore", reason: reason, confirmation: @confirmation
      )
      result = nil

      @content.class.transaction do
        content = lock_content(@content)
        if content.active_content? && content.restore_idempotency_key_digest == digest
          unless revision_replayed?(
            content, key, "restore", operation_digest: request_operation_digest
          ) && secure_match?(reason, content.revisions.find_by!(request_id_digest: digest).reason) &&
              secure_match?(@confirmation, content.title)
            raise LifecycleError, "website_content_idempotency_key_reused"
          end
          result = ServiceResult.success(content: content, replayed: true)
          next
        end
        raise LifecycleError, "website_content_already_purged" if content.purged?
        raise LifecycleError, "website_content_not_discarded" unless content.discarded?
        raise LifecycleError, "website_content_confirmation_mismatch" unless secure_match?(@confirmation, content.title)
        assert_idempotency_unused!(content, digest)
        assert_version!(content, expected)

        discard_revision = content.revisions.where(event_type: "discard").ordered.first
        snapshot = discard_revision&.snapshot || {}
        validation = RestoreValidator.call(content: content, snapshot: snapshot)
        blockers = validation.value.fetch(:blockers)
        unless blockers.empty?
          raise LifecycleError.new("website_content_restore_blocked", blockers: blockers)
        end

        before = ContentSnapshot.call(content: content)
        RevisionRecorder.call(
          content: content,
          actor: @actor,
          event_type: "restore",
          reason: reason,
          request_id: key,
          operation_digest: request_operation_digest
        )
        attributes = {
          status: "draft",
          published_at: nil,
          scheduled_at: nil,
          discarded_at: nil,
          discarded_by_id: nil,
          discard_reason: nil,
          purge_at: nil,
          discard_idempotency_key_digest: nil,
          restore_idempotency_key_digest: digest
        }
        if content.is_a?(Website::Page) && snapshot["website_theme_id"].present?
          attributes[:website_theme_id] = snapshot["website_theme_id"]
        end
        content.update!(attributes)
        audit!(
          actor: @actor,
          action: "website.#{content.class.model_name.element}.restored",
          resource: content,
          request_id: key,
          reason: reason,
          before_state: before.except("blocks", "body"),
          after_state: { status: content.status, lock_version: content.lock_version }
        )
        result = ServiceResult.success(content: content, replayed: false)
      end
      result
    rescue LifecycleError => error
      failure(error)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
      ServiceResult.failure(
        error: "website_content_restore_failed",
        code: "website_content_restore_failed",
        errors: error.respond_to?(:record) ? error.record.errors.to_hash : nil
      )
    end

    private

    def secure_match?(left, right)
      return false unless left.bytesize == right.to_s.bytesize

      ActiveSupport::SecurityUtils.secure_compare(left, right.to_s)
    end

    def assert_idempotency_unused!(content, digest)
      conflict = content.class.with_lifecycle
        .where(restore_idempotency_key_digest: digest)
        .where.not(id: content.id)
        .exists?
      raise LifecycleError, "website_content_idempotency_key_reused" if conflict
    end
  end
end
