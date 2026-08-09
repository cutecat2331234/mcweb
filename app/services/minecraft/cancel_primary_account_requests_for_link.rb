# frozen_string_literal: true

module Minecraft
  class CancelPrimaryAccountRequestsForLink < ApplicationService
    def initialize(identity_link:, actor:, reason:)
      @identity_link = identity_link
      @actor = actor
      @reason = reason.to_s.strip.presence || "identity_link_unavailable"
    end

    def call
      cancelled = []
      Minecraft::PrimaryAccountChangeRequest.pending
        .where(
          "target_identity_link_id = :id OR source_identity_link_id = :id",
          id: @identity_link.id
        )
        .find_each do |request_record|
          request_record.lock!
          next unless request_record.pending?

          request_record.update!(
            status: "cancelled",
            decided_by: @actor,
            decision_reason: @reason,
            resolved_at: Time.current
          )
          Administration::AuditLogger.call(
            actor: @actor,
            action: "minecraft.primary_account_change_cancelled",
            resource: request_record,
            reason: @reason,
            metadata: { unlinked_identity_link_id: @identity_link.id }
          )
          cancelled << request_record
        end

      ActiveRecord.after_all_transactions_commit do
        cancelled.each { |request_record| Minecraft::PrimaryAccountNotifications.request_resolved(request_record) }
      end
      ServiceResult.success(cancelled_count: cancelled.length, requests: cancelled)
    end
  end
end
