# frozen_string_literal: true

module Admin
  module System
    class IpBansController < BaseController
      before_action -> { require_permission("system.bans.manage") }

      def index
        bans = Administration::IpBan.order(created_at: :desc).limit(100)

        render inertia: "Admin/Generic/Index", props: {
          title: t("mcweb.user_copy.ip_bans_title"),
          columns: [
            { key: "ip_address", label: "IP" },
            { key: "reason", label: t("mcweb.user_copy.reason") },
            { key: "expires_at", label: t("mcweb.user_copy.expires_at") },
            { key: "created_at", label: t("mcweb.user_copy.created_at") }
          ],
          rows: bans.map do |ban|
            {
              id: ban.id,
              ip_address: ban.ip_address,
              reason: ban.reason || "—",
              expires_at: ban.expires_at ? l(ban.expires_at, format: :short) : t("mcweb.user_copy.permanent"),
              created_at: l(ban.created_at, format: :short)
            }
          end,
          newPath: nil
        }
      end

      def create
        result = Administration::BanIp.call(
          ip_address: params[:ip_address],
          actor: current_user,
          reason: params[:reason],
          expires_at: params[:expires_at].present? ? Time.zone.parse(params[:expires_at]) : nil
        )

        if result.success?
          redirect_to admin_system_ip_bans_path, notice: t("mcweb.flash.ip_banned")
        else
          redirect_to admin_system_ip_bans_path, alert: service_error_message(result)
        end
      end

      def destroy
        ban = Administration::IpBan.find(params[:id])
        ban.destroy!
        redirect_to admin_system_ip_bans_path, notice: t("mcweb.flash.ip_unbanned")
      end
    end
  end
end
