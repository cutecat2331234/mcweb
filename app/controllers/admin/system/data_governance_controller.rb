# frozen_string_literal: true

module Admin
  module System
    class DataGovernanceController < BaseController
      before_action -> { require_admin_module!("system") }
      before_action -> { require_permission("data_governance.read") }, only: :index
      before_action -> { require_permission("data_governance.policies.manage") }, only: :update_policy
      before_action -> { require_permission("data_governance.holds.manage") }, only: %i[create_hold release_hold]
      before_action -> { require_permission("data_governance.content.delete") }, only: :soft_delete
      before_action -> { require_permission("data_governance.content.restore") }, only: :restore
      before_action -> { require_permission("data_governance.content.purge") }, only: :purge

      def index
        DataGovernance::RetentionPolicy.ensure_defaults!
        policies = DataGovernance::RetentionPolicy.order(:resource_type).to_a
        records = DataGovernance::ContentLifecycleRecord
          .includes(:deleted_by, :restored_by, :purged_by)
          .recent_first
          .limit(200)
          .to_a
        holds = DataGovernance::RetentionHold
          .includes(:created_by, :released_by)
          .order(created_at: :desc, id: :desc)
          .limit(200)
          .to_a

        no_store!
        render inertia: "Admin/System/DataGovernance/Index", props: {
          policies: policies.map { |policy| serialize_policy(policy) },
          records: records.map { |record| serialize_record(record) },
          holds: holds.map { |hold| serialize_hold(hold) },
          resourceTypes: DataGovernance::ContentRegistry.entries.map { |entry|
            {
              value: entry.type,
              label: resource_type_label(entry.type)
            }
          },
          summary: {
            policies: policies.size,
            activeHolds: DataGovernance::RetentionHold.effective.count,
            awaitingPurge: DataGovernance::ContentLifecycleRecord.status_soft_deleted.count,
            blocked: DataGovernance::ContentLifecycleRecord
              .status_soft_deleted
              .where.not(blocker_codes: [])
              .count
          },
          permissions: {
            managePolicies: current_user.permission?("data_governance.policies.manage"),
            manageHolds: current_user.permission?("data_governance.holds.manage"),
            softDelete: current_user.permission?("data_governance.content.delete"),
            restore: current_user.permission?("data_governance.content.restore"),
            purge: current_user.permission?("data_governance.content.purge")
          },
          paths: {
            policy: admin_system_data_governance_policy_path("__ID__"),
            createHold: admin_system_data_governance_holds_path,
            releaseHold: admin_system_data_governance_release_hold_path("__ID__"),
            softDelete: admin_system_data_governance_soft_delete_path,
            restore: admin_system_data_governance_restore_path("__ID__"),
            purge: admin_system_data_governance_purge_path("__ID__")
          }
        }
      end

      def update_policy
        policy = DataGovernance::RetentionPolicy.find(params[:id])
        attributes = policy_params
        attributes[:retention_days] = nil if attributes[:retention_days].blank?
        result = DataGovernance::UpdateRetentionPolicy.call(
          policy:,
          actor: current_user,
          attributes:,
          reason: params[:reason],
          request_id: request.request_id
        )
        render_result(result) { { policy: serialize_policy(result.value.fetch(:policy)) } }
      end

      def create_hold
        target = resolve_target!
        result = DataGovernance::PlaceRetentionHold.call(
          target:,
          actor: current_user,
          reason: params[:reason],
          policy_reference: params[:policy_reference],
          expires_at: params[:expires_at],
          request_id: request.request_id
        )
        render_result(result) do
          {
            hold: serialize_hold(result.value.fetch(:hold)),
            replayed: result.value.fetch(:replayed, false)
          }
        end
      end

      def release_hold
        hold = DataGovernance::RetentionHold.find_by!(public_id: params[:id])
        result = DataGovernance::ReleaseRetentionHold.call(
          hold:,
          actor: current_user,
          reason: params[:reason],
          request_id: request.request_id
        )
        render_result(result) do
          {
            hold: serialize_hold(result.value.fetch(:hold)),
            replayed: result.value.fetch(:replayed)
          }
        end
      end

      def soft_delete
        result = DataGovernance::SoftDeleteContent.call(
          target: resolve_target!,
          actor: current_user,
          reason: params[:reason],
          request_id: request.request_id
        )
        render_result(result) do
          {
            record: serialize_record(result.value.fetch(:record)),
            replayed: result.value.fetch(:replayed)
          }
        end
      end

      def restore
        record = lifecycle_record
        result = DataGovernance::RestoreContent.call(
          record:,
          actor: current_user,
          reason: params[:reason],
          request_id: request.request_id
        )
        render_result(result) do
          {
            record: serialize_record(result.value.fetch(:record)),
            replayed: result.value.fetch(:replayed)
          }
        end
      end

      def purge
        result = DataGovernance::PermanentlyPurgeContent.call(
          record: lifecycle_record,
          actor: current_user,
          reason: params[:reason],
          request_id: request.request_id
        )
        render_result(result) do
          {
            record: serialize_record(result.value.fetch(:record)),
            replayed: result.value.fetch(:replayed)
          }
        end
      end

      private

      def resolve_target!
        DataGovernance::ContentRegistry.resolve_reference(
          target_type: params.require(:target_type),
          reference: params.require(:target_reference)
        ) || raise(ActiveRecord::RecordNotFound)
      end

      def lifecycle_record
        DataGovernance::ContentLifecycleRecord.find_by!(public_id: params[:id])
      end

      def policy_params
        params.permit(
          :retention_days,
          :user_deletable,
          :moderator_restorable,
          :legal_hold_supported,
          :notes
        ).to_h.symbolize_keys
      end

      def render_result(result)
        no_store!
        if result.success?
          render json: yield
        else
          render json: {
            error: result.code.presence || result.error,
            errors: result.errors,
            blockers: result.value.is_a?(Hash) ? result.value[:blockers] : nil
          }.compact, status: service_error_status(result)
        end
      end

      def serialize_policy(policy)
        {
          id: policy.id,
          resourceType: policy.resource_type,
          resourceLabel: resource_type_label(policy.resource_type),
          retentionDays: policy.retention_days,
          userDeletable: policy.user_deletable?,
          moderatorRestorable: policy.moderator_restorable?,
          legalHoldSupported: policy.legal_hold_supported?,
          notes: policy.notes,
          activeHolds: DataGovernance::RetentionHold.effective
            .where(target_type: policy.resource_type)
            .count,
          awaitingPurge: DataGovernance::ContentLifecycleRecord.status_soft_deleted
            .where(target_type: policy.resource_type)
            .count
        }
      end

      def serialize_record(record)
        target_label =
          if record.status_purged?
            resource_type_label(record.target_type)
          else
            record.target_snapshot["label"].presence ||
              record.target_snapshot[:label].presence ||
              "##{record.target_id}"
          end

        {
          id: record.public_id,
          targetType: record.target_type,
          targetLabel: target_label,
          targetReference: record.target_snapshot["public_id"].presence ||
            record.target_snapshot[:public_id].presence ||
            record.target_id.to_s,
          status: record.status,
          softDeletedAt: record.soft_deleted_at&.iso8601,
          purgeAfter: record.purge_after&.iso8601,
          restoredAt: record.restored_at&.iso8601,
          purgedAt: record.purged_at&.iso8601,
          deletionReason: record.deletion_reason,
          restorationReason: record.restoration_reason,
          purgeReason: record.purge_reason,
          blockerCodes: Array(record.blocker_codes),
          purgeAttempts: record.purge_attempts,
          actors: {
            deletedBy: serialize_actor(record.deleted_by),
            restoredBy: serialize_actor(record.restored_by),
            purgedBy: serialize_actor(record.purged_by)
          }
        }
      end

      def serialize_hold(hold)
        target = hold.resolved_target
        snapshot =
          if target && DataGovernance::ContentRegistry.supported?(target)
            DataGovernance::ContentRegistry.snapshot(target)
          else
            {}
          end
        {
          id: hold.public_id,
          targetType: hold.target_type,
          targetLabel: snapshot[:label].presence || "##{hold.target_id}",
          targetReference: snapshot[:public_id].presence || hold.target_id.to_s,
          status: hold.status,
          effective: hold.effective?,
          reason: hold.reason,
          policyReference: hold.policy_reference,
          expiresAt: hold.expires_at&.iso8601,
          releasedAt: hold.released_at&.iso8601,
          releaseReason: hold.release_reason,
          createdAt: hold.created_at.iso8601,
          createdBy: serialize_actor(hold.created_by),
          releasedBy: serialize_actor(hold.released_by)
        }
      end

      def serialize_actor(actor)
        actor && {
          username: actor.username,
          publicId: actor.public_id
        }
      end

      def resource_type_label(resource_type)
        key = "mcweb.data_governance.resource_types.#{resource_type.to_s.underscore.tr('/', '_')}"
        t(key, default: resource_type.to_s.demodulize.underscore.humanize)
      end

      def no_store!
        response.set_header("Cache-Control", "private, no-store")
      end
    end
  end
end
