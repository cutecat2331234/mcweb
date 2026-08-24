# frozen_string_literal: true

module Website
  class MutateTheme < ApplicationService
    include ThemeVersionContract

    OPERATIONS = %w[create update activate].freeze
    MUTABLE_ATTRIBUTES = %i[name key tokens].freeze

    def initialize(operation:, theme:, actor:, attributes: {}, expected_lock_version: nil)
      @operation = operation.to_s
      @theme = theme
      @actor = actor
      @attributes = attributes.to_h.symbolize_keys.slice(*MUTABLE_ATTRIBUTES)
      @expected_lock_version = expected_lock_version
    end

    def call
      raise LifecycleError, "website_theme_operation_invalid" unless OPERATIONS.include?(@operation)

      case @operation
      when "create" then create_theme
      when "update" then update_theme
      when "activate" then activate_theme
      end
    rescue LifecycleError => error
      theme_failure(error)
    rescue ActiveRecord::RecordInvalid => error
      failed_theme = error.record.is_a?(Theme) ? error.record : @theme
      ServiceResult.failure(
        error: "website_theme_mutation_failed",
        code: "website_theme_mutation_failed",
        errors: error.record.errors.to_hash(true),
        value: { theme: failed_theme }
      )
    rescue ActiveRecord::RecordNotUnique
      ServiceResult.failure(
        error: "website_theme_key_taken",
        code: "website_theme_key_taken",
        value: { theme: @theme }
      )
    rescue ActiveRecord::StaleObjectError
      ServiceResult.failure(
        error: "website_theme_conflict",
        code: "website_theme_conflict",
        value: { theme: @theme }
      )
    end

    private

    def create_theme
      result = nil
      Theme.transaction do
        @theme.assign_attributes(@attributes)
        @theme.save!
        revision = record_revision!(
          theme: @theme,
          snapshot: ThemeSnapshot.call(theme: @theme),
          event_type: "create",
          source_lock_version: 0
        )
        record_mutation_audit!(
          action: "website.theme.created",
          theme: @theme,
          revision: revision,
          before_snapshot: nil
        )
        result = ServiceResult.success(theme: @theme, revision: revision)
      end
      result
    end

    def update_theme
      expected = theme_expected_version!(@expected_lock_version)
      result = nil
      Theme.transaction do
        theme = Theme.lock.find(@theme.id)
        assert_theme_version!(theme, expected)
        before_snapshot = ThemeSnapshot.call(theme: theme)
        revision = record_revision!(
          theme: theme,
          snapshot: before_snapshot,
          event_type: "update",
          source_lock_version: expected
        )
        theme.assign_attributes(@attributes)
        advance_theme_timestamp(theme)
        theme.save!
        record_mutation_audit!(
          action: "website.theme.updated",
          theme: theme,
          revision: revision,
          before_snapshot: before_snapshot
        )
        result = ServiceResult.success(theme: theme, revision: revision)
      end
      result
    end

    def activate_theme
      expected = theme_expected_version!(@expected_lock_version)
      result = nil
      Theme.transaction do
        themes = Theme.lock.order(:id).to_a
        theme = themes.find { |candidate| candidate.id == @theme.id }
        raise LifecycleError, "website_theme_not_found" unless theme

        assert_theme_version!(theme, expected)
        themes.select { |candidate| candidate.active? && candidate.id != theme.id }.each do |active_theme|
          deactivate_theme!(active_theme)
        end

        before_snapshot = ThemeSnapshot.call(theme: theme)
        revision = record_revision!(
          theme: theme,
          snapshot: before_snapshot,
          event_type: "activate",
          source_lock_version: expected
        )
        theme.active = true
        advance_theme_timestamp(theme)
        theme.save!
        record_mutation_audit!(
          action: "website.theme.activated",
          theme: theme,
          revision: revision,
          before_snapshot: before_snapshot
        )
        result = ServiceResult.success(theme: theme, revision: revision)
      end
      result
    end

    def deactivate_theme!(theme)
      before_snapshot = ThemeSnapshot.call(theme: theme)
      source_version = theme.lock_version
      revision = record_revision!(
        theme: theme,
        snapshot: before_snapshot,
        event_type: "deactivate",
        source_lock_version: source_version
      )
      theme.active = false
      theme.save!
      record_mutation_audit!(
        action: "website.theme.deactivated",
        theme: theme,
        revision: revision,
        before_snapshot: before_snapshot
      )
    end

    def record_revision!(theme:, snapshot:, event_type:, source_lock_version:)
      ThemeRevisionRecorder.call(
        theme: theme,
        snapshot: snapshot,
        actor: @actor,
        event_type: event_type,
        source_lock_version: source_lock_version
      )
    end

    def record_mutation_audit!(action:, theme:, revision:, before_snapshot:)
      after_snapshot = ThemeSnapshot.call(theme: theme)
      changed_paths = before_snapshot ? theme_changed_paths(before_snapshot, after_snapshot) : after_snapshot.keys
      record_theme_audit!(
        actor: @actor,
        action: action,
        resource: theme,
        metadata: {
          revision_number: revision.revision_number,
          source_lock_version: revision.source_lock_version,
          current_lock_version: theme.lock_version,
          changed_paths: changed_paths
        },
        before_state: before_snapshot ? safe_snapshot_state(before_snapshot, revision.source_lock_version) : {},
        after_state: safe_theme_state(theme)
      )
    end

    def safe_snapshot_state(snapshot, lock_version)
      {
        name: snapshot.fetch("name"),
        key: snapshot.fetch("key"),
        active: snapshot.fetch("active"),
        token_count: count_theme_token_leaves(snapshot.fetch("tokens")),
        lock_version: lock_version
      }
    end
  end
end
