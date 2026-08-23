# frozen_string_literal: true

module Website
  class ContentUpdate < ApplicationService
    include LifecycleContract

    def initialize(content:, attributes:, actor:, expected_lock_version: nil, request_id: nil)
      @content = content
      @attributes = attributes.to_h
      @actor = actor
      @expected_lock_version = Integer(expected_lock_version, exception: false)
      @request_id = request_id.to_s.presence
    end

    def call
      raise LifecycleError, "website_content_version_required" if @expected_lock_version.nil?
      normalize_idempotency_key!(@request_id)
      request_operation_digest = operation_digest(event: "update", attributes: @attributes)
      result = nil
      @content.class.transaction do
        content = lock_content(@content)
        raise LifecycleError, "website_content_unavailable" unless content.active_content?
        if revision_replayed?(
          content, @request_id, "update", operation_digest: request_operation_digest
        )
          result = ServiceResult.success(content: content, replayed: true)
          next
        end
        assert_version!(content, @expected_lock_version)

        candidate = content.dup
        candidate.assign_attributes(@attributes)
        if candidate.attributes.slice(*@attributes.keys.map(&:to_s)) ==
            content.attributes.slice(*@attributes.keys.map(&:to_s))
          result = ServiceResult.success(content: content, replayed: true)
          next
        end

        RevisionRecorder.call(
          content: content,
          actor: @actor,
          event_type: "update",
          request_id: @request_id,
          operation_digest: request_operation_digest
        )
        before = ContentSnapshot.call(content: content)
        content.update!(@attributes)
        audit!(
          actor: @actor,
          action: "website.#{content.class.model_name.element}.updated",
          resource: content,
          request_id: @request_id,
          before_state: before.except("blocks", "body"),
          after_state: ContentSnapshot.call(content: content).except("blocks", "body")
        )
        result = ServiceResult.success(content: content, replayed: false)
      end
      result
    rescue LifecycleError => error
      failure(error)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
      ServiceResult.failure(errors: error.respond_to?(:record) ? error.record.errors.to_hash : { base: [ "website_content_conflict" ] })
    end
  end
end
