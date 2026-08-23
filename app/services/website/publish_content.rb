# frozen_string_literal: true

module Website
  class PublishContent < ApplicationService
    include LifecycleContract

    def initialize(content:, publish_at: nil, actor: nil, expected_lock_version: nil, request_id: nil)
      @content = content
      @publish_at = publish_at
      @actor = actor
      @expected_lock_version = Integer(expected_lock_version, exception: false)
      @request_id = request_id.to_s.presence
    end

    def call
      if @actor
        raise LifecycleError, "website_content_version_required" if @expected_lock_version.nil?
        normalize_idempotency_key!(@request_id)
      end
      result = nil
      @content.class.transaction do
        content = lock_content(@content)
        raise LifecycleError, "website_content_unavailable" unless content.active_content?

        event_type, attributes = transition
        request_operation_digest = operation_digest(
          event: event_type,
          publish_at: event_type == "schedule" ? @publish_at : nil
        )
        if revision_replayed?(
          content, @request_id, event_type, operation_digest: request_operation_digest
        )
          result = ServiceResult.success(content: content, replayed: true)
          next
        end
        assert_version!(content, @expected_lock_version) if @expected_lock_version
        if replay?(content, event_type)
          result = ServiceResult.success(content: content, replayed: true)
          next
        end

        before = ContentSnapshot.call(content: content)
        RevisionRecorder.call(
          content: content,
          actor: @actor,
          event_type: event_type,
          request_id: @request_id,
          operation_digest: @request_id ? request_operation_digest : nil
        )
        content.update!(attributes)
        audit!(
          actor: @actor,
          action: "website.#{content.class.model_name.element}.#{event_type == 'publish' ? 'published' : 'scheduled'}",
          resource: content,
          request_id: @request_id,
          before_state: before.except("blocks", "body"),
          after_state: {
            status: content.status,
            published_at: content.published_at&.iso8601,
            scheduled_at: content.scheduled_at&.iso8601,
            lock_version: content.lock_version
          }
        )
        result = ServiceResult.success(content: content, replayed: false)
      end
      result
    rescue LifecycleError => error
      failure(error)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
      ServiceResult.failure(
        error: "website_content_publish_failed",
        code: "website_content_publish_failed",
        errors: error.respond_to?(:record) ? error.record.errors.to_hash : nil
      )
    end

    private

    def transition
      if @publish_at.present? && @publish_at.future?
        [ "schedule", { status: "scheduled", scheduled_at: @publish_at, published_at: nil } ]
      else
        [ "publish", { status: "published", published_at: Time.current, scheduled_at: nil } ]
      end
    end

    def replay?(content, event_type)
      if event_type == "publish"
        content.published? && content.scheduled_at.nil?
      else
        content.scheduled? && content.scheduled_at&.to_i == @publish_at&.to_i
      end
    end
  end
end
