# frozen_string_literal: true

module Commerce
  class GrantMembership < ApplicationService
    def initialize(user:, membership_type:, source: "purchase", source_order_item: nil,
                   grant_game_permissions: true, idempotency_key: nil)
      @user = user
      @membership_type = membership_type
      @source = source
      @source_order_item = source_order_item
      @grant_game_permissions = grant_game_permissions
      @idempotency_key = idempotency_key.to_s.presence
    end

    def call
      if @source_order_item && Commerce::UserMembership.exists?(source_order_item_id: @source_order_item.id)
        existing = Commerce::UserMembership.find_by!(source_order_item_id: @source_order_item.id)
        protection = protect_dispute_rights(existing)
        return protection if protection.failure?

        return ServiceResult.success(existing)
      end

      membership = nil
      command_result = nil
      protection_result = nil

      Commerce::UserMembership.transaction do
        @user.lock!
        @membership_type.lock!
        starts_at, expires_at = calculate_window
        membership = Commerce::UserMembership.create!(
          user: @user,
          membership_type: @membership_type,
          status: :active,
          starts_at: starts_at,
          expires_at: expires_at,
          source: @source,
          source_order_item: @source_order_item
        )

        protection_result = protect_dispute_rights(membership)
        raise ActiveRecord::Rollback if protection_result.failure?

        if @source_order_item
          Commerce::OrderEvent.create!(
            order: @source_order_item.order,
            event_type: "membership_granted",
            metadata: {
              membership_type_id: @membership_type.id,
              user_membership_id: membership.id,
              expires_at: membership.expires_at&.iso8601
            }
          )
        end

        if @grant_game_permissions && @membership_type.game_permission_enabled?
          grant_on_purchase = membership.currently_active? && (
            !@membership_type.game_permission_website_managed? ||
              first_active_membership_for_type?(membership)
          )
          if grant_on_purchase
            command_result = Commerce::DispatchMembershipCommands.call(
              user: @user,
              membership_type: @membership_type,
              commands: @membership_type.resolved_grant_commands,
              idempotency_key: @idempotency_key
            )
            raise ActiveRecord::Rollback if command_result.failure?
          end
        end
      end

      return protection_result if protection_result&.failure?
      return command_result if command_result&.failure?

      ServiceResult.success(membership)
    rescue ActiveRecord::RecordNotUnique
      if @source_order_item
        existing = Commerce::UserMembership.find_by(source_order_item_id: @source_order_item.id)
        if existing
          protection = protect_dispute_rights(existing)
          return protection if protection.failure?

          return ServiceResult.success(existing)
        end
      end

      raise
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def calculate_window
      now = Time.current
      latest_expiry = Commerce::UserMembership
        .active
        .where(user: @user, store_membership_type_id: @membership_type.id)
        .where("expires_at IS NULL OR expires_at > ?", now)
        .maximum(:expires_at)

      starts_at = if latest_expiry.present? && latest_expiry > now
                    latest_expiry
      else
                    now
      end

      expires_at = if @membership_type.permanent?
                     nil
      else
                     starts_at + @membership_type.duration_for_membership
      end

      [ starts_at, expires_at ]
    end

    def first_active_membership_for_type?(membership)
      Commerce::UserMembership
        .currently_active
        .where(user: @user, store_membership_type_id: @membership_type.id)
        .where.not(id: membership.id)
        .none?
    end

    def protect_dispute_rights(membership)
      return ServiceResult.success(skipped: true) unless @source_order_item

      Commerce::Disputes::ProtectGrantedSubject.call(
        order: @source_order_item.order,
        subject: membership
      )
    end
  end
end
