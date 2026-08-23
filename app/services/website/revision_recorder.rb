# frozen_string_literal: true

module Website
  class RevisionRecorder < ApplicationService
    include LifecycleContract

    def initialize(content:, actor:, event_type:, reason: nil, request_id: nil, operation_digest: nil)
      @content = content
      @actor = actor
      @event_type = event_type.to_s
      @reason = reason.to_s.strip.presence
      @request_id = request_id.to_s.strip.presence
      @operation_digest = operation_digest.to_s.presence
    end

    def call
      validate_contract!
      @content.class.transaction do
        content = @content.class.with_lifecycle.lock.find(@content.id)
        digest = @request_id && idempotency_digest(@request_id)
        if digest
          existing = content.revisions.find_by(request_id_digest: digest)
          if existing
            return existing if existing.event_type == @event_type

            raise LifecycleError, "website_content_idempotency_key_reused"
          end
        end

        content.revisions.create!(
          author: @actor,
          revision_number: (content.revisions.unscope(:order).maximum(:revision_number) || 0) + 1,
          snapshot: ContentSnapshot.call(content: content),
          event_type: @event_type,
          reason: @reason,
          request_id_digest: digest,
          operation_digest: @operation_digest,
          source_lock_version: content.lock_version
        )
      end
    end

    private

    def validate_contract!
      allowed = @content.revisions.klass::EVENT_TYPES
      raise LifecycleError, "website_revision_event_invalid" unless allowed.include?(@event_type)
      if @reason&.length.to_i > MAX_REASON_LENGTH
        raise LifecycleError, "website_content_reason_too_long"
      end
      normalize_idempotency_key!(@request_id) if @request_id
      valid_digest = @operation_digest.present? &&
        @operation_digest.match?(Website::RecoverableContent::IDEMPOTENCY_DIGEST_PATTERN)
      unless @request_id.present? == valid_digest
        raise LifecycleError, "website_content_idempotency_contract_invalid"
      end
    end
  end
end
