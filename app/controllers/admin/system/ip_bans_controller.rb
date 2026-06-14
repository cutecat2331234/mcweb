# frozen_string_literal: true

module Admin
  module System
    class IpBansController < BaseController
      before_action -> { require_permission("admin.access") }

      def index
        bans = Administration::IpBan.order(created_at: :desc).limit(100)

        render inertia: "Admin/Generic/Index", props: {
          title: "IP 封禁",
          columns: [
            { key: "ip_address", label: "IP" },
            { key: "reason", label: "原因" },
            { key: "expires_at", label: "过期" },
            { key: "created_at", label: "创建时间" }
          ],
          rows: bans.map do |ban|
            {
              id: ban.id,
              ip_address: ban.ip_address,
              reason: ban.reason || "—",
              expires_at: ban.expires_at ? l(ban.expires_at, format: :short) : "永久",
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
          redirect_to admin_system_ip_bans_path, notice: "IP 已封禁。"
        else
          redirect_to admin_system_ip_bans_path, alert: service_error_message(result)
        end
      end

      def destroy
        ban = Administration::IpBan.find(params[:id])
        ban.destroy!
        redirect_to admin_system_ip_bans_path, notice: "IP 封禁已解除。"
      end
    end
  end
end
