# frozen_string_literal: true

module Website
  class ArchiveContent < ApplicationService
    include LifecycleContract

    def initialize(content:, actor:, expected_lock_version: nil, request_id: nil)
      @content = content
      @actor = actor
      @expected_lock_version = Integer(expected_lock_version, exception: false)
      @request_id = request_id.to_s.presence
    end

    def call
      raise LifecycleError, "website_content_version_required" if @expected_lock_version.nil?
      normalize_idempotency_key!(@request_id)
      request_operation_digest = operation_digest(event: "archive")
      result = nil
      @content.class.transaction do
        content = lock_content(@content)
        raise LifecycleError, "website_content_unavailable" unless content.active_content?
        if revision_replayed?(
          content, @request_id, "archive", operation_digest: request_operation_digest
        )
          result = ServiceResult.success(content: content, replayed: true)
          next
        end
        assert_version!(content, @expected_lock_version) if @expected_lock_version
        if content.archived?
          result = ServiceResult.success(content: content, replayed: true)
          next
        end

        before = ContentSnapshot.call(content: content)
        RevisionRecorder.call(
          content: content,
          actor: @actor,
          event_type: "archive",
          request_id: @request_id,
          operation_digest: request_operation_digest
        )
        content.update!(status: "archived", published_at: nil, scheduled_at: nil)
        audit!(
          actor: @actor,
          action: "website.#{content.class.model_name.element}.archived",
          resource: content,
          request_id: @request_id,
          before_state: before.except("blocks", "body"),
          after_state: { status: content.status, lock_version: content.lock_version }
        )
        result = ServiceResult.success(content: content, replayed: false)
      end
      result
    rescue LifecycleError => error
      failure(error)
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(errors: error.record.errors.to_hash)
    end
  end
end
