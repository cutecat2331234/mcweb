# frozen_string_literal: true

module DataGovernance
  class DeletionPolicy < ApplicationService
    def initialize(target:)
      @target = target
    end

    def call
      blockers = []
      blockers << "legal_hold" if active_hold?
      blockers << "unresolved_report" if unresolved_report?
      blockers << "unresolved_moderation_case" if unresolved_moderation_case?
      blockers << "open_dispute" if unresolved_dispute?

      ServiceResult.success(
        allowed: blockers.empty?,
        blockers: blockers.uniq,
        policy: policy_payload
      )
    end

    private

    def active_hold?
      hold_target_references.any? do |reference|
        RetentionHold.effective.where(
          target_type: reference.target_type,
          target_id: reference.target_ids
        ).exists?
      end
    end

    def unresolved_report?
      return false unless defined?(Community::Report)

      evidence_target_references.any? do |reference|
        Community::Report.where(
          reportable_type: reference.target_type,
          reportable_id: reference.target_ids,
          status: "pending"
        ).exists?
      end
    end

    def unresolved_moderation_case?
      return false unless defined?(Community::ModerationCase)

      direct = evidence_target_references.any? do |reference|
        Community::ModerationCase.active_queue.where(
          source_type: reference.target_type,
          source_id: reference.target_ids
        ).exists?
      end
      return true if direct

      report_case = defined?(Community::Report) && evidence_target_references.any? do |reference|
        report_ids = Community::Report.where(
          reportable_type: reference.target_type,
          reportable_id: reference.target_ids
        ).select(:id)
        Community::ModerationCase.active_queue
          .where(source_type: "Community::Report", source_id: report_ids)
          .exists?
      end
      return true if report_case

      @target.is_a?(User) &&
        Community::ModerationCase.active_queue.where(target_user_id: @target.id).exists?
    end

    def unresolved_dispute?
      return false unless defined?(Commerce::Dispute)

      scope =
        case @target
        when User
          Commerce::Dispute.joins(:order).where(store_orders: { user_id: @target.id })
        when Commerce::Order
          @target.disputes
        when Payments::Record
          @target.disputes
        when Commerce::Dispute
          Commerce::Dispute.where(id: @target.id)
        end
      return false unless scope

      scope.where.not(status: Commerce::Dispute::TERMINAL_STATUSES).exists?
    end

    def evidence_target_references
      @evidence_target_references ||= ContentRegistry.evidence_reference_sets(@target)
    end

    def hold_target_references
      @hold_target_references ||= ContentRegistry.hold_reference_sets(@target)
    end

    def policy_payload
      policy = RetentionPolicy.find_by(resource_type: @target.class.base_class.name)
      return nil unless policy

      {
        resource_type: policy.resource_type,
        retention_days: policy.retention_days,
        user_deletable: policy.user_deletable?,
        moderator_restorable: policy.moderator_restorable?,
        legal_hold_supported: policy.legal_hold_supported?
      }
    end
  end
end
