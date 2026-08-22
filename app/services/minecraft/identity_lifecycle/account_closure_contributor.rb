# frozen_string_literal: true

module Minecraft
  module IdentityLifecycle
    module AccountClosureContributor
      CLOSURE_REASON = "account_closed"

      module_function

      def preflight(context:)
        links = active_links(context.user).includes(:player_profile).to_a
        blocker = blocker_for(context.user, links)
        return blocker if blocker

        ::Identity::AccountClosure::Contribution.ready(
          details: preflight_details(context.user, links)
        )
      end

      def execute(context:, preflight:)
        unless preflight.ready?
          return ::Identity::AccountClosure::Contribution.failed(
            code: "minecraft_account_close_preflight_invalid"
          )
        end

        execution = nil
        Minecraft::IdentityLink.transaction do
          context.user.lock!
          links = links_to_revoke(context.user).lock.order(:id).to_a
          active = links.select { |link| link.unlinked_at.nil? }
          lock_shared_profiles!(links)
          blocker = blocker_for(context.user, active)
          if blocker
            execution = ::Identity::AccountClosure::Contribution.failed(
              code: blocker.code,
              details: { outcome: "preflight_changed" }
            )
            next
          end

          requests = pending_requests(context.user).lock.order(:id).to_a
          legacy = Minecraft::Identity.where(user_id: context.user.id).lock.order(:id).to_a
          snapshots = snapshots_for(links:, requests:, legacy:)

          revoke_links!(links, at: context.at)
          cancel_requests!(requests, actor: context.user, at: context.at)
          Minecraft::Identity.where(id: legacy.map(&:id)).delete_all if legacy.any?

          execution = ::Identity::AccountClosure::Contribution.completed(
            details: {
              outcome: mutation_count(links:, requests:, legacy:).positive? ?
                "minecraft_bindings_revoked" : "minecraft_bindings_already_revoked",
              revoked_bindings: links.length,
              cancelled_primary_requests: requests.length,
              removed_legacy_bindings: legacy.length,
              shared_profiles_retained: links.map(&:player_profile_id).uniq.length
            },
            compensation_data: snapshots
          )
        end
        execution
      end

      def compensate(context:, execution:)
        snapshots = (execution.compensation_data || {}).to_h.deep_stringify_keys
        restored_links = Array(snapshots["links"])
        restored_requests = Array(snapshots["requests"])
        restored_legacy = Array(snapshots["legacy_identities"])

        Minecraft::IdentityLink.transaction do
          context.user.lock!
          restore_rows(Minecraft::IdentityLink, restored_links)
          restore_rows(Minecraft::PrimaryAccountChangeRequest, restored_requests)
          Minecraft::Identity.insert_all!(restored_legacy) if restored_legacy.any?
        end

        ::Identity::AccountClosure::Contribution.compensated(
          details: {
            restored_bindings: restored_links.length,
            restored_primary_requests: restored_requests.length,
            restored_legacy_bindings: restored_legacy.length
          }
        )
      end

      def active_links(user)
        Minecraft::IdentityLink.active.where(user_id: user.id).order(:id)
      end
      private_class_method :active_links

      def links_to_revoke(user)
        Minecraft::IdentityLink
          .where(user_id: user.id)
          .where("unlinked_at IS NULL OR primary_account = TRUE")
      end
      private_class_method :links_to_revoke

      def pending_requests(user)
        Minecraft::PrimaryAccountChangeRequest.pending.where(user_id: user.id)
      end
      private_class_method :pending_requests

      def blocker_for(user, links)
        profile_ids = links.map(&:player_profile_id).uniq
        if profile_ids.any? && Minecraft::PlayerSession.active.exists?(player_profile_id: profile_ids)
          return ::Identity::AccountClosure::Contribution.blocked(
            code: "minecraft_account_close_active_session",
            details: { outcome: "active_player_session", affected_bindings: links.length }
          )
        end

        links.each do |link|
          result = Minecraft::IdentityUnlinkRestrictions.check(
            user:,
            identity_link: link
          )
          next if result.success?

          return ::Identity::AccountClosure::Contribution.blocked(
            code: result.code,
            details: { outcome: "identity_unlink_restricted", affected_bindings: 1 }
          )
        end
        nil
      end
      private_class_method :blocker_for

      def preflight_details(user, links)
        {
          outcome: links.any? || Minecraft::Identity.where(user_id: user.id).exists? ?
            "minecraft_bindings_ready" : "minecraft_bindings_absent",
          current_bindings: links.length,
          legacy_bindings: Minecraft::Identity.where(user_id: user.id).count,
          pending_primary_requests: pending_requests(user).count,
          retained_obligations: retained_obligation_count(user, links)
        }
      end
      private_class_method :preflight_details

      def retained_obligation_count(user, links)
        targets = {
          user.class.base_class.name => [ user.id ],
          Minecraft::IdentityLink.base_class.name => links.map(&:id),
          Minecraft::PlayerProfile.base_class.name => links.map(&:player_profile_id)
        }
        targets.sum do |target_type, target_ids|
          next 0 if target_ids.compact.empty?

          DataGovernance::RetentionHold.effective
            .where(target_type:, target_id: target_ids.compact.uniq)
            .count
        end
      end
      private_class_method :retained_obligation_count

      def lock_shared_profiles!(links)
        profile_ids = links.map(&:player_profile_id).uniq.sort
        Minecraft::PlayerProfile.where(id: profile_ids).order(:id).lock.load if profile_ids.any?
      end
      private_class_method :lock_shared_profiles!

      def snapshots_for(links:, requests:, legacy:)
        {
          "links" => links.map do |link|
            link.attributes.slice(
              "id", "unlinked_at", "primary_account", "lock_version", "updated_at"
            )
          end,
          "requests" => requests.map do |request_record|
            request_record.attributes.slice(
              "id", "status", "decided_by_id", "decision_reason", "resolved_at",
              "applied_at", "lock_version", "updated_at"
            )
          end,
          "legacy_identities" => legacy.map(&:attributes)
        }
      end
      private_class_method :snapshots_for

      def revoke_links!(links, at:)
        links.each do |link|
          link.update!(
            unlinked_at: link.unlinked_at || at,
            primary_account: false
          )
        end
      end
      private_class_method :revoke_links!

      def cancel_requests!(requests, actor:, at:)
        requests.each do |request_record|
          request_record.update!(
            status: "cancelled",
            decided_by: actor,
            decision_reason: CLOSURE_REASON,
            resolved_at: at
          )
        end
      end
      private_class_method :cancel_requests!

      def mutation_count(links:, requests:, legacy:)
        links.length + requests.length + legacy.length
      end
      private_class_method :mutation_count

      def restore_rows(model, snapshots)
        snapshots.each do |snapshot|
          attributes = snapshot.to_h.deep_stringify_keys
          id = attributes.delete("id")
          model.where(id:).update_all(attributes)
        end
      end
      private_class_method :restore_rows
    end
  end
end
