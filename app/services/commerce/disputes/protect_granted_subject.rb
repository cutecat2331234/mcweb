# frozen_string_literal: true

module Commerce
  module Disputes
    class ProtectGrantedSubject < ApplicationService
      SUPPORTED_SUBJECTS = [
        Commerce::UserEntitlement,
        Commerce::UserMembership
      ].freeze

      def initialize(order:, subject:, membership_was_externally_synced: true)
        @order = order
        @subject = subject
        @membership_was_externally_synced = membership_was_externally_synced
      end

      def call
        return failure("dispute_granted_subject_invalid") unless valid_input?

        result = nil
        Commerce::Dispute.transaction do
          order = Commerce::Order.lock.find(@order.id)
          subject = @subject.class.lock.find(@subject.id)
          unless subject_belongs_to_order?(subject, order:)
            result = failure("dispute_granted_subject_binding_mismatch")
            next
          end

          applied = 0
          changed = 0
          applicable_disputes(order).each do |dispute|
            action = dispute.rights_revoked? ? "revoke" : "freeze"
            before = subject_state(subject)
            protection = Commerce::Disputes::RightsPolicy.call(
              dispute:,
              action:,
              idempotency_prefix: idempotency_prefix(dispute, subject),
              reason: "granted_during_payment_dispute",
              subjects: [ subject ],
              externally_unsynced_memberships: externally_unsynced_memberships(subject)
            )
            unless protection.success?
              subject.errors.add(
                :base,
                protection.error.presence || "dispute right protection failed"
              )
              raise ActiveRecord::RecordInvalid.new(subject)
            end

            applied += 1
            changed += protection.value.fetch(:changed)
            if protection.value.fetch(:changed).positive?
              Administration::AuditLogger.call(
                action: "commerce.dispute_granted_subject_protected",
                resource: subject,
                before_state: before,
                after_state: subject_state(subject),
                metadata: {
                  dispute_public_id: dispute.public_id,
                  order_public_id: order.public_id,
                  source_order_item_id: subject.source_order_item_id,
                  subject_type: subject.class.name,
                  subject_id: subject.id,
                  rights_action: action
                }
              )
            end
          end

          result = ServiceResult.success(subject:, applied:, changed:)
        end

        result
      rescue ActiveRecord::RecordInvalid => error
        ServiceResult.failure(errors: error.record.errors.to_hash)
      end

      private

      def valid_input?
        @order&.persisted? &&
          @subject&.persisted? &&
          SUPPORTED_SUBJECTS.any? { |type| @subject.is_a?(type) }
      end

      def subject_belongs_to_order?(subject, order:)
        subject.user_id == order.user_id &&
          subject.source_order_item_id.present? &&
          order.items.where(id: subject.source_order_item_id).exists?
      end

      def applicable_disputes(order)
        order.disputes
          .where(rights_status: %w[frozen revoked])
          .where("liability_cents > 0")
          .order(
            Arel.sql(
              "CASE store_disputes.rights_status " \
              "WHEN 'frozen' THEN 0 ELSE 1 END"
            ),
            :id
          )
          .lock
          .to_a
      end

      def idempotency_prefix(dispute, subject)
        "dispute-granted-subject:#{dispute.id}:#{subject.class.name}:#{subject.id}"
      end

      def externally_unsynced_memberships(subject)
        return [] unless subject.is_a?(Commerce::UserMembership)
        return [] unless @membership_was_externally_synced == false

        [ subject ]
      end

      def subject_state(subject)
        {
          risk_hold_dispute_id: subject.risk_hold_dispute_id,
          risk_held_at: subject.risk_held_at&.iso8601(6),
          currently_active: subject.currently_active?,
          status: subject.respond_to?(:status) ? subject.status : nil,
          revoked_at: subject.respond_to?(:revoked_at) ?
            subject.revoked_at&.iso8601(6) :
            nil
        }.compact
      end

      def failure(code)
        ServiceResult.failure(error: code, code:)
      end
    end
  end
end
