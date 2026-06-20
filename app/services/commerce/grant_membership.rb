# frozen_string_literal: true

module Commerce
  class GrantMembership < ApplicationService
    def initialize(user:, membership_type:, source: "purchase", source_order_item: nil, grant_game_permissions: true)
      @user = user
      @membership_type = membership_type
      @source = source
      @source_order_item = source_order_item
      @grant_game_permissions = grant_game_permissions
    end

    def call
      if @source_order_item && Commerce::UserMembership.exists?(source_order_item_id: @source_order_item.id)
        existing = Commerce::UserMembership.find_by!(source_order_item_id: @source_order_item.id)
        return ServiceResult.success(existing)
      end

      starts_at, expires_at = calculate_window
      should_grant_commands = @grant_game_permissions

      membership = Commerce::UserMembership.create!(
        user: @user,
        membership_type: @membership_type,
        status: :active,
        starts_at: starts_at,
        expires_at: expires_at,
        source: @source,
        source_order_item: @source_order_item
      )

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

      if should_grant_commands && @membership_type.game_permission_enabled?
        grant_on_purchase = !@membership_type.game_permission_website_managed? || first_active_membership_for_type?(membership)
        if grant_on_purchase
          Commerce::DispatchMembershipCommands.call(
            user: @user,
            membership_type: @membership_type,
            commands: @membership_type.resolved_grant_commands
          )
        end
      end

      ServiceResult.success(membership)
    rescue ActiveRecord::RecordNotUnique
      if @source_order_item
        existing = Commerce::UserMembership.find_by(source_order_item_id: @source_order_item.id)
        return ServiceResult.success(existing) if existing
      end

      raise
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def calculate_window
      now = Time.current
      latest_expiry = Commerce::UserMembership
        .currently_active
        .where(user: @user, store_membership_type_id: @membership_type.id)
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
  end
end
