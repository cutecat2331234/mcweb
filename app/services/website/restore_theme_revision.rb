# frozen_string_literal: true

module Website
  class RestoreThemeRevision < ApplicationService
    include ThemeVersionContract

    def initialize(theme:, revision:, actor:, reason:, confirmation:,
                   expected_lock_version:, idempotency_key:)
      @theme = theme
      @revision = revision
      @actor = actor
      @reason = reason
      @confirmation = confirmation.to_s
      @expected_lock_version = expected_lock_version
      @idempotency_key = idempotency_key
    end

    def call
      reason = normalize_theme_reason!(@reason)
      key = normalize_theme_idempotency_key!(@idempotency_key)
      expected = theme_expected_version!(@expected_lock_version)
      request_digest = theme_idempotency_digest(key)
      requested_operation_digest = theme_operation_digest(
        theme_id: @theme.id,
        source_revision_id: @revision.id,
        source_revision_number: @revision.revision_number,
        actor_id: @actor&.id,
        reason: reason,
        confirmation: @confirmation,
        expected_lock_version: expected
      )
      result = nil

      Theme.transaction do
        theme = Theme.lock.find(@theme.id)
        revision = theme.revisions.find_by(id: @revision.id)
        raise LifecycleError, "website_theme_revision_not_found" unless revision

        replay = ThemeRevision.find_by(request_id_digest: request_digest)
        if replay
          validate_replay!(
            replay,
            theme: theme,
            revision: revision,
            operation_digest: requested_operation_digest
          )
          result = ServiceResult.success(theme: theme, revision: replay, replayed: true)
          next
        end

        unless secure_theme_match?(@confirmation, revision.revision_number.to_s)
          raise LifecycleError, "website_theme_confirmation_mismatch"
        end
        assert_theme_version!(theme, expected)

        target_snapshot = ThemeSnapshot.call(snapshot: revision.snapshot)
        before_snapshot = ThemeSnapshot.call(theme: theme)
        active = theme.active?
        successor = ThemeRevisionRecorder.call(
          theme: theme,
          snapshot: before_snapshot,
          event_type: "restore",
          actor: @actor,
          reason: reason,
          source_lock_version: expected,
          source_revision: revision,
          request_id_digest: request_digest,
          operation_digest: requested_operation_digest
        )
        theme.assign_attributes(
          name: target_snapshot.fetch("name"),
          key: target_snapshot.fetch("key"),
          tokens: target_snapshot.fetch("tokens"),
          active: active
        )
        advance_theme_timestamp(theme)
        theme.save!
        record_restore_audit!(
          theme: theme,
          source_revision: revision,
          successor: successor,
          reason: reason,
          expected: expected,
          before_snapshot: before_snapshot
        )
        result = ServiceResult.success(theme: theme, revision: successor, replayed: false)
      end
      result
    rescue LifecycleError => error
      theme_failure(error)
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(
        error: "website_theme_restore_failed",
        code: "website_theme_restore_failed",
        errors: error.record.errors.to_hash(true)
      )
    rescue ActiveRecord::RecordNotUnique
      ServiceResult.failure(
        error: "website_theme_idempotency_key_reused",
        code: "website_theme_idempotency_key_reused"
      )
    rescue ActiveRecord::StaleObjectError
      ServiceResult.failure(
        error: "website_theme_conflict",
        code: "website_theme_conflict"
      )
    end

    private

    def validate_replay!(replay, theme:, revision:, operation_digest:)
      valid = replay.website_theme_id == theme.id &&
        replay.event_type == "restore" &&
        replay.source_revision_id == revision.id &&
        secure_theme_digest_match?(replay.operation_digest, operation_digest)
      raise LifecycleError, "website_theme_idempotency_key_reused" unless valid
    end

    def record_restore_audit!(theme:, source_revision:, successor:, reason:, expected:,
                              before_snapshot:)
      after_snapshot = ThemeSnapshot.call(theme: theme)
      record_theme_audit!(
        actor: @actor,
        action: "website.theme.revision_restored",
        resource: theme,
        reason: reason,
        metadata: {
          source_revision_number: source_revision.revision_number,
          submitted_lock_version: expected,
          current_lock_version: theme.lock_version,
          successor_revision_number: successor.revision_number,
          changed_paths: theme_changed_paths(before_snapshot, after_snapshot)
        },
        before_state: {
          name: before_snapshot.fetch("name"),
          key: before_snapshot.fetch("key"),
          active: before_snapshot.fetch("active"),
          token_count: count_theme_token_leaves(before_snapshot.fetch("tokens")),
          lock_version: expected
        },
        after_state: safe_theme_state(theme)
      )
    end
  end
end
