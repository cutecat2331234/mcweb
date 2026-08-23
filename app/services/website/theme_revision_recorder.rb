# frozen_string_literal: true

module Website
  class ThemeRevisionRecorder < ApplicationService
    def initialize(theme:, snapshot:, actor:, event_type:, source_lock_version:, reason: nil,
                   source_revision: nil, request_id_digest: nil, operation_digest: nil)
      @theme = theme
      @snapshot = ThemeSnapshot.call(snapshot: snapshot)
      @actor = actor
      @event_type = event_type.to_s
      @reason = reason.to_s.strip.presence
      @source_lock_version = source_lock_version
      @source_revision = source_revision
      @request_id_digest = request_id_digest
      @operation_digest = operation_digest
    end

    def call
      raise Website::LifecycleError, "website_theme_revision_event_invalid" unless
        ThemeRevision::EVENT_TYPES.include?(@event_type)

      @theme.revisions.create!(
        actor: @actor,
        snapshot: @snapshot,
        revision_number: next_revision_number,
        event_type: @event_type,
        reason: @reason,
        source_lock_version: @source_lock_version,
        source_revision: @source_revision,
        request_id_digest: @request_id_digest,
        operation_digest: @operation_digest
      )
    end

    private

    def next_revision_number
      (@theme.revisions.unscope(:order).maximum(:revision_number) || 0) + 1
    end
  end
end
