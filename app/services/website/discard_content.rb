# frozen_string_literal: true

module Website
  class DiscardContent < ApplicationService
    include LifecycleContract

    def initialize(content:, actor:, reason:, confirmation:, expected_lock_version:, idempotency_key:,
                   replacement_page_public_id: nil, at: Time.current)
      @content = content
      @actor = actor
      @reason = reason
      @confirmation = confirmation.to_s
      @expected_lock_version = expected_lock_version
      @idempotency_key = idempotency_key
      @replacement_page_public_id = replacement_page_public_id.to_s.presence
      @at = at
    end

    def call
      reason = normalize_reason!(@reason)
      key = normalize_idempotency_key!(@idempotency_key)
      digest = idempotency_digest(key)
      expected = expected_version!(@expected_lock_version)
      request_operation_digest = operation_digest(
        event: "discard",
        reason: reason,
        confirmation: @confirmation,
        replacement_page_public_id: @replacement_page_public_id
      )
      result = nil

      @content.class.transaction do
        content, replacement = lock_targets
        if content.purged?
          raise LifecycleError, "website_content_already_purged"
        end
        if content.discarded?
          if content.discard_idempotency_key_digest == digest
            unless revision_replayed?(
              content, key, "discard", operation_digest: request_operation_digest
            ) && secure_match?(reason, content.discard_reason) &&
                secure_match?(@confirmation, content.title)
              raise LifecycleError, "website_content_idempotency_key_reused"
            end
            result = ServiceResult.success(content: content, replayed: true)
            next
          end
          raise LifecycleError, "website_content_already_discarded"
        end
        raise LifecycleError, "website_content_confirmation_mismatch" unless
          secure_match?(@confirmation, content.title)
        assert_idempotency_unused!(content, :discard_idempotency_key_digest, digest)
        assert_version!(content, expected)
        validate_home_replacement!(content, replacement)

        before = ContentSnapshot.call(content: content)
        RevisionRecorder.call(
          content: content,
          actor: @actor,
          event_type: "discard",
          reason: reason,
          request_id: key,
          operation_digest: request_operation_digest
        )
        content.update!(
          status: "archived",
          published_at: nil,
          scheduled_at: nil,
          discarded_at: @at,
          discarded_by: @actor,
          discard_reason: reason,
          purge_at: @at + retention_days.days,
          discard_idempotency_key_digest: digest,
          restore_idempotency_key_digest: nil
        )
        audit!(
          actor: @actor,
          action: "website.#{content.class.model_name.element}.discarded",
          resource: content,
          request_id: key,
          reason: reason,
          before_state: before.except("blocks", "body"),
          after_state: {
            discarded_at: content.discarded_at.iso8601,
            purge_at: content.purge_at.iso8601,
            replacement_page_public_id: replacement&.public_id
          }
        )
        result = ServiceResult.success(content: content, replayed: false)
      end
      result
    rescue LifecycleError => error
      failure(error)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
      ServiceResult.failure(
        error: "website_content_discard_failed",
        code: "website_content_discard_failed",
        errors: error.respond_to?(:record) ? error.record.errors.to_hash : nil
      )
    end

    private

    def secure_match?(left, right)
      right = right.to_s
      return false unless left.bytesize == right.bytesize

      ActiveSupport::SecurityUtils.secure_compare(left, right)
    end

    def lock_targets
      return [ lock_content(@content), nil ] unless @content.is_a?(Website::Page)

      replacement = if @replacement_page_public_id
        Website::Page.find_by(public_id: @replacement_page_public_id)
      end
      ids = [ @content.id, replacement&.id ].compact.uniq.sort
      locked = Website::Page.with_lifecycle.where(id: ids).order(:id).lock.index_by(&:id)
      [ locked.fetch(@content.id), replacement && locked[replacement.id] ]
    end

    def validate_home_replacement!(content, replacement)
      return unless content.is_a?(Website::Page)
      return unless content.page_type == "home" && content.published?

      unless replacement && replacement.id != content.id && replacement.active_content? &&
          replacement.page_type == "home" && replacement.published?
        raise LifecycleError, "website_home_replacement_required"
      end
    end

    def assert_idempotency_unused!(content, column, digest)
      conflict = content.class.with_lifecycle.where(column => digest).where.not(id: content.id).exists?
      raise LifecycleError, "website_content_idempotency_key_reused" if conflict
    end
  end
end
