# frozen_string_literal: true

module Admin
  module System
    # XenForo-style email ban / filter management.
    class EmailBansController < BaseController
      before_action -> { require_permission("admin.access") }
      before_action :set_ban, only: %i[edit update destroy]

      def index
        bans = Administration::EmailBan.order(created_at: :desc).limit(200)

        render inertia: "Admin/Generic/Index", props: {
          title: t("mcweb.admin.email_bans.title"),
          subtitle: t("mcweb.admin.email_bans.subtitle"),
          columns: [
            { key: "pattern", label: t("mcweb.admin.email_bans.col_pattern"), link: true },
            { key: "reason", label: t("mcweb.admin.email_bans.col_reason") },
            { key: "expires_at", label: t("mcweb.admin.email_bans.col_expires") },
            { key: "created_at", label: t("mcweb.admin.email_bans.col_created") }
          ],
          rows: bans.map do |ban|
            {
              id: ban.id,
              pattern: ban.pattern,
              reason: ban.reason.presence || "—",
              expires_at: ban.expires_at ? l(ban.expires_at, format: :short) : t("mcweb.admin.email_bans.permanent"),
              created_at: l(ban.created_at, format: :short),
              url: admin_system_email_ban_path(ban)
            }
          end,
          actions: [ { label: t("mcweb.admin.email_bans.action_new"), href: new_admin_system_email_ban_path } ]
        }
      end

      def new
        render inertia: "Admin/System/EmailBans/Form", props: form_props(Administration::EmailBan.new)
      end

      def create
        ban = Administration::EmailBan.new(
          pattern: params.dig(:email_ban, :pattern).to_s.strip,
          reason: params.dig(:email_ban, :reason),
          expires_at: parse_expiry(params.dig(:email_ban, :expires_at)),
          banned_by: current_user
        )

        if ban.save
          Administration::AuditLogger.call(actor: current_user, action: "admin.email_banned", metadata: { pattern: ban.pattern })
          redirect_to admin_system_email_bans_path, notice: t("mcweb.flash.email_banned")
        else
          render inertia: "Admin/System/EmailBans/Form", props: form_props(ban), status: :unprocessable_entity
        end
      end

      def edit
        render inertia: "Admin/System/EmailBans/Form", props: form_props(@ban, editing: true)
      end

      def update
        if @ban.update(
          pattern: params.dig(:email_ban, :pattern).to_s.strip,
          reason: params.dig(:email_ban, :reason),
          expires_at: parse_expiry(params.dig(:email_ban, :expires_at))
        )
          redirect_to admin_system_email_bans_path, notice: t("mcweb.flash.email_ban_updated")
        else
          render inertia: "Admin/System/EmailBans/Form", props: form_props(@ban, editing: true), status: :unprocessable_entity
        end
      end

      def destroy
        @ban.destroy!
        redirect_to admin_system_email_bans_path, notice: t("mcweb.flash.email_unbanned")
      end

      private

      def set_ban
        @ban = Administration::EmailBan.find(params[:id])
      end

      def parse_expiry(value)
        return nil if value.blank?

        Time.zone.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def form_props(ban, editing: false)
        {
          title: editing ? t("mcweb.admin.email_bans.form_edit") : t("mcweb.admin.email_bans.form_new"),
          email_ban: {
            pattern: ban.pattern || "",
            reason: ban.reason || "",
            expires_at: ban.expires_at&.strftime("%Y-%m-%dT%H:%M")
          },
          errors: ban.errors.to_hash.transform_values { |msgs| msgs.join("；") },
          submitUrl: editing ? admin_system_email_ban_path(ban) : admin_system_email_bans_path,
          method: editing ? "patch" : "post",
          backUrl: admin_system_email_bans_path,
          deleteUrl: editing ? admin_system_email_ban_path(ban) : nil
        }
      end
    end
  end
end
