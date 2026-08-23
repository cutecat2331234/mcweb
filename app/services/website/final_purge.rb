# frozen_string_literal: true

module Website
  class FinalPurge < ApplicationService
    include LifecycleContract

    class << self
      def confirmation_for(content)
        "#{content.class.model_name.element}:#{content.slug}"
      end
    end

    def initialize(content:, actor:, reason:, confirmation:, expected_lock_version:, idempotency_key:,
                   authorization_token: nil, background: false, at: Time.current)
      @content = content
      @actor = actor
      @reason = reason
      @confirmation = confirmation.to_s
      @expected_lock_version = expected_lock_version
      @idempotency_key = idempotency_key
      @authorization_token = authorization_token
      @authorization_method = nil
      @background = background
      @at = at
    end

    def call
      reason = normalize_reason!(@reason)
      key = normalize_idempotency_key!(@idempotency_key)
      digest = idempotency_digest(key)
      expected = expected_version!(@expected_lock_version)
      request_operation_digest = operation_digest(
        event: "purge",
        reason: reason,
        confirmation: @confirmation,
        background: @background
      )
      if (replayed = replayed_content(reason, digest, key, request_operation_digest))
        validate_replay_actor!
        return ServiceResult.success(content: replayed, replayed: true)
      end
      validate_authorization!(reason, key)
      result = nil

      @content.class.transaction do
        content = lock_content(@content)
        if content.purged?
          if content.purge_idempotency_key_digest == digest
            unless replay_fingerprint_matches?(content, reason)
              raise LifecycleError, "website_content_idempotency_key_reused"
            end
            revision_replayed?(
              content, key, "purge", operation_digest: request_operation_digest
            )
            result = ServiceResult.success(content: content, replayed: true)
            next
          end
          raise LifecycleError, "website_content_already_purged"
        end
        raise LifecycleError, "website_content_confirmation_mismatch" unless
          secure_match?(@confirmation, self.class.confirmation_for(content))
        assert_idempotency_unused!(content, digest)
        assert_version!(content, expected)

        eligibility = PurgeEligibility.call(content: content, at: @at)
        blockers = eligibility.value.fetch(:blockers)
        unless blockers.empty?
          raise LifecycleError.new("website_content_purge_blocked", blockers: blockers)
        end

        before = ContentSnapshot.call(content: content)
        RevisionRecorder.call(
          content: content,
          actor: @actor,
          event_type: "purge",
          reason: reason,
          request_id: key,
          operation_digest: request_operation_digest
        )
        content.blocks.delete_all if content.is_a?(Website::Page)
        content.update!(tombstone_attributes(content, reason, digest))
        audit!(
          actor: @actor,
          action: "website.#{content.class.model_name.element}.purged",
          resource: content,
          request_id: key,
          reason: reason,
          before_state: before.except("blocks", "body"),
          after_state: {
            purged_at: content.purged_at.iso8601,
            tombstone: true,
            background: @background
          },
          metadata: purge_authorization_metadata
        )
        result = ServiceResult.success(content: content, replayed: false)
      end
      result
    rescue LifecycleError => error
      audit_blocked_attempt(reason, key, error) if defined?(reason) && defined?(key)
      failure(error)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
      ServiceResult.failure(
        error: "website_content_purge_failed",
        code: "website_content_purge_failed",
        errors: error.respond_to?(:record) ? error.record.errors.to_hash : nil
      )
    end

    private

    def replayed_content(reason, digest, key, request_operation_digest)
      content = @content.class.with_lifecycle.find(@content.id)
      return unless content.purged? && content.purge_idempotency_key_digest == digest
      unless replay_fingerprint_matches?(content, reason)
        raise LifecycleError, "website_content_idempotency_key_reused"
      end
      revision_replayed?(
        content, key, "purge", operation_digest: request_operation_digest
      )

      content
    end

    def replay_fingerprint_matches?(content, reason)
      secure_match?(reason, content.purge_reason.to_s) &&
        secure_match?(@confirmation, self.class.confirmation_for(content))
    end

    def validate_replay_actor!
      if @background
        raise LifecycleError, "website_content_purge_authorization_invalid" if @actor || @authorization_token
      elsif !@actor&.permission?("website.content.purge")
        raise LifecycleError, "website_content_purge_unauthorized"
      end
    end

    def validate_authorization!(reason, key)
      if @background
        raise LifecycleError, "website_content_purge_authorization_invalid" if @actor || @authorization_token
        return
      end

      unless @actor&.permission?("website.content.purge")
        raise LifecycleError, "website_content_purge_unauthorized"
      end

      authorization = PurgeAuthorization.call(
        actor: @actor,
        content: @content,
        reason: reason,
        request_id: key,
        authorization_token: @authorization_token
      )
      unless authorization.success?
        raise LifecycleError, authorization.code || "website_content_step_up_required"
      end

      @authorization_method = authorization.value.fetch(:authorization_method)
    end

    def tombstone_attributes(content, reason, digest)
      common = {
        status: "archived",
        title: content.public_id,
        author_id: nil,
        seo: {},
        translations: {},
        published_at: nil,
        scheduled_at: nil,
        purged_at: @at,
        purged_by: @actor,
        purge_reason: reason,
        purge_idempotency_key_digest: digest
      }
      if content.is_a?(Website::Page)
        common.merge(website_theme_id: nil)
      else
        common.merge(summary: nil, body: nil)
      end
    end

    def audit_blocked_attempt(reason, key, error)
      return if @background || @actor.nil?

      Administration::AuditLogger.call(
        actor: @actor,
        action: "website.#{@content.class.model_name.element}.purge_blocked",
        resource: @content,
        request_id: key,
        reason: reason,
        metadata: {
          error: error.code,
          blockers: error.details[:blockers],
          background: @background,
          authorization_method: @authorization_method
        }.compact
      )
    end

    def purge_authorization_metadata
      return { background: true } if @background

      {
        background: false,
        authorization_method: @authorization_method,
        authorization_digest: Digest::SHA256.hexdigest(@authorization_token.to_s)
      }
    end

    def secure_match?(left, right)
      return false unless left.bytesize == right.bytesize

      ActiveSupport::SecurityUtils.secure_compare(left, right)
    end

    def assert_idempotency_unused!(content, digest)
      conflict = content.class.with_lifecycle
        .where(purge_idempotency_key_digest: digest)
        .where.not(id: content.id)
        .exists?
      raise LifecycleError, "website_content_idempotency_key_reused" if conflict
    end
  end
end
