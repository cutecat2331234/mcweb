# frozen_string_literal: true

module Minecraft
  class PrimaryAccountNotifications
    REVIEW_PERMISSION = "minecraft.primary_accounts.review"

    class << self
      def request_created(request_record)
        notify(
          request_record.user,
          type: "minecraft.primary_account.requested",
          title_key: "mcweb.notifications.minecraft_primary_account_requested.title",
          body_key: "mcweb.notifications.minecraft_primary_account_requested.body",
          path: "/app/minecraft/link",
          interpolation: account_interpolation(request_record.target_identity_link)
        )

        approval_recipients.find_each do |recipient|
          notify(
            recipient,
            type: "minecraft.primary_account.review_required",
            title_key: "mcweb.notifications.minecraft_primary_account_review_required.title",
            body_key: "mcweb.notifications.minecraft_primary_account_review_required.body",
            path: "/admin/minecraft/players",
            interpolation: {
              member: request_record.user.display_name,
              account: account_name(request_record.target_identity_link)
            }
          )
        end
      end

      def request_resolved(request_record)
        notify(
          request_record.user,
          type: "minecraft.primary_account.#{request_record.status}",
          title_key: "mcweb.notifications.minecraft_primary_account_#{request_record.status}.title",
          body_key: "mcweb.notifications.minecraft_primary_account_#{request_record.status}.body",
          path: "/app/minecraft/link",
          interpolation: account_interpolation(request_record.target_identity_link)
        )
      end

      def administrator_override(event)
        notify(
          event.user,
          type: "minecraft.primary_account.administrator_override",
          title_key: "mcweb.notifications.minecraft_primary_account_administrator_override.title",
          body_key: "mcweb.notifications.minecraft_primary_account_administrator_override.body",
          path: "/app/minecraft/link",
          interpolation: account_interpolation(event.to_identity_link)
        )
      end

      private

      def approval_recipients
        User.not_banned
            .where(account_type: %w[staff admin owner])
            .where.not(id: nil)
            .select { |candidate| candidate.can_access_admin? && candidate.permission?(REVIEW_PERMISSION) }
            .then { |records| User.where(id: records.map(&:id)) }
      end

      def notify(user, type:, title_key:, body_key:, path:, interpolation:)
        I18n.with_locale(user.locale.presence || I18n.default_locale) do
          Notification.notify!(
            user: user,
            notification_type: type,
            title: I18n.t(title_key, **interpolation),
            body: I18n.t(body_key, **interpolation),
            metadata: { path: path }
          )
        end
      end

      def account_interpolation(link)
        { account: account_name(link) }
      end

      def account_name(link)
        link.player_profile.active_identity&.username || link.player_profile.public_id
      end
    end
  end
end
