# frozen_string_literal: true

module Website
  class RestoreRevision < ApplicationService
    include LifecycleContract

    def initialize(content:, revision:, actor:, reason:, confirmation:, expected_lock_version:,
                   idempotency_key:)
      @content = content
      @revision = revision
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
        event: "revision_restore",
        source_revision_id: @revision.id,
        reason: reason,
        confirmation: @confirmation
      )
      result = nil

      @content.class.transaction do
        content = lock_content(@content)
        raise LifecycleError, "website_content_already_purged" if content.purged?
        unless @revision.class.where(id: @revision.id, revision_parent_key => content.id).exists?
          raise LifecycleError, "website_revision_not_found"
        end
        if content.active_content? && content.restore_idempotency_key_digest == digest
          replay_revision = content.revisions.find_by(request_id_digest: digest)
          unless revision_replayed?(
            content, key, "revision_restore", operation_digest: request_operation_digest
          ) &&
              secure_match?(reason, replay_revision.reason) &&
              secure_match?(@confirmation, content.title)
            raise LifecycleError, "website_content_idempotency_key_reused"
          end
          result = ServiceResult.success(content: content, replayed: true)
          next
        end
        raise LifecycleError, "website_content_confirmation_mismatch" unless
          secure_match?(@confirmation, content.title)
        assert_version!(content, expected)
        assert_idempotency_unused!(content, digest)

        snapshot = @revision.snapshot.to_h.stringify_keys
        validation = RestoreValidator.call(content: content, snapshot: snapshot)
        blockers = validation.value.fetch(:blockers)
        unless blockers.empty?
          raise LifecycleError.new("website_content_restore_blocked", blockers: blockers)
        end

        before = ContentSnapshot.call(content: content)
        RevisionRecorder.call(
          content: content,
          actor: @actor,
          event_type: "revision_restore",
          reason: reason,
          request_id: key,
          operation_digest: request_operation_digest
        )
        apply_snapshot!(content, snapshot, digest)
        audit!(
          actor: @actor,
          action: "website.#{content.class.model_name.element}.revision_restored",
          resource: content,
          request_id: key,
          reason: reason,
          before_state: before.except("blocks", "body"),
          after_state: {
            source_revision_id: @revision.id,
            source_revision_number: @revision.revision_number,
            status: content.status,
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
        error: "website_revision_restore_failed",
        code: "website_revision_restore_failed",
        errors: error.respond_to?(:record) ? error.record.errors.to_hash : nil
      )
    end

    private

    def revision_parent_key
      @content.is_a?(Website::Page) ? :website_page_id : :website_article_id
    end

    def apply_snapshot!(content, snapshot, digest)
      common = {
        title: snapshot.fetch("title"),
        slug: snapshot.fetch("slug"),
        status: "draft",
        seo: snapshot["seo"] || {},
        translations: snapshot["translations"] || {},
        published_at: nil,
        scheduled_at: nil,
        discarded_at: nil,
        discarded_by_id: nil,
        discard_reason: nil,
        purge_at: nil,
        discard_idempotency_key_digest: nil,
        restore_idempotency_key_digest: digest
      }

      if content.is_a?(Website::Page)
        content.update!(
          common.merge(
            page_type: snapshot.fetch("page_type", "custom"),
            website_theme_id: snapshot["website_theme_id"]
          )
        )
        content.blocks.delete_all
        Array(snapshot["blocks"]).each do |block_data|
          block = block_data.to_h.stringify_keys
          content.blocks.create!(
            block_type: block.fetch("block_type"),
            position: block.fetch("position"),
            settings: block["settings"] || {},
            translations: block["translations"] || {},
            visible: block.fetch("visible", true)
          )
        end
      else
        content.update!(
          common.merge(
            article_type: snapshot.fetch("article_type", "news"),
            summary: snapshot["summary"],
            body: snapshot["body"]
          )
        )
      end
    end

    def secure_match?(left, right)
      right = right.to_s
      return false unless left.bytesize == right.bytesize

      ActiveSupport::SecurityUtils.secure_compare(left, right)
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
