# frozen_string_literal: true

module Community
  class ManageSectionLifecycle < ApplicationService
    class AuditFailure < StandardError; end

    OPERATIONS = %w[archive restore destroy].freeze
    CONFIRMATION_VERBS = {
      "archive" => "ARCHIVE",
      "restore" => "RESTORE",
      "destroy" => "DELETE"
    }.freeze

    def self.confirmation_for(section:, operation:)
      verb = CONFIRMATION_VERBS.fetch(operation.to_s)
      "#{verb} #{section.slug}"
    end

    def initialize(section:, actor:, operation:, reason:, confirmation:, ip_address: nil, user_agent: nil, request_id: nil)
      @section = section
      @actor = actor
      @operation = operation.to_s
      @reason = reason.to_s.strip
      @confirmation = confirmation.to_s.strip
      @ip_address = ip_address
      @user_agent = user_agent
      @request_id = request_id
    end

    def call
      return failure(:invalid_operation) unless OPERATIONS.include?(@operation)
      return failure(:permission_denied) unless authorized?
      return failure(:reason_required) if @reason.blank?
      return failure(:reason_too_long) if @reason.length > 1_000
      return failure(:confirmation_mismatch) unless confirmation_valid?

      lock_attempts = 0
      begin
        Community::Section.transaction do
          @section = Community::SectionHierarchyLock.lock!(@section).sole
          case @operation
          when "archive" then archive!
          when "restore" then restore!
          when "destroy" then destroy!
          end
        end
      rescue Community::SectionHierarchyLock::HierarchyChanged, ActiveRecord::Deadlocked
        lock_attempts += 1
        fresh_section = Community::Section.find_by(id: @section.id)
        if lock_attempts <= 2 && fresh_section
          @section = fresh_section
          retry
        end
        failure(:conflict)
      rescue ActiveRecord::RecordNotFound
        failure(:conflict)
      end
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    rescue ActiveRecord::DeleteRestrictionError, ActiveRecord::InvalidForeignKey
      failure(:delete_blocked)
    rescue AuditFailure
      failure(:audit_failed)
    end

    private

    def authorized?
      permission = @operation == "destroy" ? "forum.sections.delete" : "forum.sections.lifecycle"
      @actor&.permission?(permission)
    end

    def archive!
      return failure(:already_archived) if @section.archived_at.present?

      impact = Community::SectionLifecycleImpact.call(section: @section)
      before_state = lifecycle_state
      @section.update!(
        archived_at: Time.current,
        archived_by: @actor,
        archived_reason: @reason
      )
      audit!("admin.forum_section_archived", impact:, before_state:, after_state: lifecycle_state)
      ServiceResult.success(section: @section, impact: impact)
    end

    def restore!
      return failure(:not_archived) if @section.archived_at.blank?

      impact = Community::SectionLifecycleImpact.call(section: @section)
      before_state = lifecycle_state
      @section.update!(archived_at: nil, archived_by: nil, archived_reason: nil)
      audit!("admin.forum_section_restored", impact:, before_state:, after_state: lifecycle_state)
      ServiceResult.success(section: @section, impact: impact)
    end

    def destroy!
      return failure(:delete_requires_archive) if @section.archived_at.blank?

      impact = Community::SectionLifecycleImpact.call(section: @section)
      return failure(:delete_has_descendants) if impact.fetch(:descendants).positive?
      return failure(:delete_has_topics) if impact.fetch(:topics).positive?
      return failure(:delete_has_moderation_cases) if impact.fetch(:moderation_cases).positive?

      snapshot = lifecycle_state.merge(name: @section.name, category_id: @section.forum_category_id)
      audit!(
        "admin.forum_section_deleted",
        impact:,
        before_state: snapshot,
        after_state: { deleted: true }
      )
      @section.destroy!
      ServiceResult.success(section_id: @section.id, impact: impact)
    end

    def confirmation_valid?
      expected = self.class.confirmation_for(section: @section, operation: @operation)
      return false unless @confirmation.bytesize == expected.bytesize

      ActiveSupport::SecurityUtils.secure_compare(@confirmation, expected)
    end

    def lifecycle_state
      {
        archived: @section.archived_at.present?,
        archived_at: @section.archived_at&.iso8601,
        archived_by_id: @section.archived_by_id,
        archived_reason: @section.archived_reason
      }
    end

    def audit!(action, impact:, before_state:, after_state:)
      result = Administration::AuditLogger.call(
        actor: @actor,
        action: action,
        resource: @section,
        metadata: {
          section_name: @section.name,
          section_slug: @section.slug,
          operation: @operation,
          impact: impact,
          confirmation_method: "typed_section_slug"
        },
        before_state: before_state,
        after_state: after_state,
        reason: @reason,
        ip_address: @ip_address,
        user_agent: @user_agent,
        request_id: @request_id
      )
      raise AuditFailure if result.failure?

      result
    end

    def failure(key)
      ServiceResult.failure(
        error: I18n.t("mcweb.services.community.section_lifecycle.#{key}")
      )
    end
  end
end
