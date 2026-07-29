# frozen_string_literal: true

module Commerce
  module Disputes
    class RightsPolicy < ApplicationService
      ACTIONS = %w[freeze revoke restore].freeze

      def initialize(dispute:, action:, idempotency_prefix:, actor: nil, reason: nil)
        @dispute = dispute
        @action = action.to_s
        @idempotency_prefix = idempotency_prefix.to_s
        @actor = actor
        @reason = reason.to_s.presence
        @membership_syncs = []
      end

      def call
        return ServiceResult.failure(error: "dispute_rights_action_invalid") unless ACTIONS.include?(@action)
        return ServiceResult.failure(error: "dispute_idempotency_invalid") if @idempotency_prefix.blank?

        changed = 0
        replayed = 0

        subjects.each do |subject|
          idempotency_key = rights_idempotency_key(subject)
          if Commerce::DisputeRightsAction.exists?(idempotency_key:)
            replayed += 1
            next
          end

          subject.lock!
          subject.reload
          before = subject_state(subject)
          apply_to_subject!(subject)
          after = subject_state(subject)

          Commerce::DisputeRightsAction.create!(
            dispute: @dispute,
            subject: subject,
            actor: @actor,
            action: @action,
            idempotency_key: idempotency_key,
            reason: @reason,
            before_state: before,
            after_state: after,
            metadata: {
              "order_public_id" => @dispute.order.public_id,
              "source_order_item_id" => subject.source_order_item_id
            }
          )
          changed += 1 if before != after
          schedule_membership_sync(subject, before:, after:)
        end

        @dispute.update!(rights_status: resulting_rights_status)
        enqueue_membership_syncs

        ServiceResult.success(
          changed: changed,
          replayed: replayed,
          rights_status: @dispute.rights_status
        )
      rescue ActiveRecord::RecordInvalid => error
        ServiceResult.failure(errors: error.record.errors.to_hash)
      end

      private

      def subjects
        item_ids = @dispute.order.items.order(:id).pluck(:id)
        entitlements = Commerce::UserEntitlement
          .where(source_order_item_id: item_ids)
          .order(:id)
          .lock
          .to_a
        memberships = Commerce::UserMembership
          .where(source_order_item_id: item_ids)
          .includes(:membership_type, :user)
          .order(:id)
          .lock
          .to_a

        entitlements + memberships
      end

      def apply_to_subject!(subject)
        case @action
        when "freeze"
          subject.update!(
            risk_hold_dispute: @dispute,
            risk_held_at: subject.risk_held_at || Time.current
          )
        when "revoke"
          attributes = {
            risk_hold_dispute: @dispute,
            risk_held_at: subject.risk_held_at || Time.current
          }
          if subject.is_a?(Commerce::UserEntitlement)
            attributes[:revoked_at] = subject.revoked_at || Time.current
          else
            attributes[:status] = "revoked"
          end
          subject.update!(attributes)
        when "restore"
          restore_subject!(subject)
        end
      end

      def restore_subject!(subject)
        replacement = replacement_dispute_for(subject)
        original = original_subject_state(subject)
        attributes = restored_attributes(subject, original)

        if replacement
          attributes[:risk_hold_dispute] = replacement
          attributes[:risk_held_at] = subject.risk_held_at || Time.current
          if replacement.rights_revoked?
            if subject.is_a?(Commerce::UserEntitlement)
              attributes[:revoked_at] ||= Time.current
            else
              attributes[:status] = "revoked"
            end
          end
        else
          attributes[:risk_hold_dispute] = nil
          attributes[:risk_held_at] = nil
        end

        subject.update!(attributes)
      end

      def replacement_dispute_for(subject)
        Commerce::Dispute
          .where(store_order_id: @dispute.store_order_id, rights_status: %w[frozen revoked])
          .where.not(id: @dispute.id)
          .joins(:rights_actions)
          .where(
            store_dispute_rights_actions: {
              subject_type: subject.class.name,
              subject_id: subject.id
            }
          )
          .order(Arel.sql("CASE store_disputes.rights_status WHEN 'revoked' THEN 0 ELSE 1 END"), :id)
          .first
      end

      def original_subject_state(subject)
        action = Commerce::DisputeRightsAction
          .where(subject: subject)
          .where(action: %w[freeze revoke])
          .order(:created_at, :id)
          .first
        action&.before_state.to_h.stringify_keys.presence || subject_state(subject)
      end

      def restored_attributes(subject, original)
        if subject.is_a?(Commerce::UserEntitlement)
          { revoked_at: parse_time(original["revoked_at"]) }
        else
          { status: original["status"].presence || "active" }
        end
      end

      def subject_state(subject)
        base = {
          "risk_hold_dispute_id" => subject.risk_hold_dispute_id,
          "risk_held_at" => subject.risk_held_at&.iso8601(6),
          "currently_active" => subject.currently_active?
        }
        if subject.is_a?(Commerce::UserEntitlement)
          base["revoked_at"] = subject.revoked_at&.iso8601(6)
        else
          base["status"] = subject.status
        end
        base
      end

      def schedule_membership_sync(subject, before:, after:)
        return unless subject.is_a?(Commerce::UserMembership)
        return if before["currently_active"] == after["currently_active"]

        @membership_syncs << [
          subject.id,
          after["currently_active"] ? "grant" : "revoke",
          rights_idempotency_key(subject)
        ]
      end

      def enqueue_membership_syncs
        jobs = @membership_syncs.uniq
        return if jobs.empty?

        ActiveRecord.after_all_transactions_commit do
          jobs.each do |membership_id, action, idempotency_key|
            Commerce::SyncDisputeMembershipRightsJob.perform_later(
              membership_id,
              action,
              idempotency_key
            )
          end
        end
      end

      def rights_idempotency_key(subject)
        [
          @idempotency_prefix,
          @action,
          subject.class.name,
          subject.id
        ].join(":")
      end

      def resulting_rights_status
        {
          "freeze" => "frozen",
          "revoke" => "revoked",
          "restore" => "restored"
        }.fetch(@action)
      end

      def parse_time(value)
        Time.zone.parse(value.to_s) if value.present?
      rescue ArgumentError
        nil
      end
    end
  end
end
