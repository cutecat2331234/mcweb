# frozen_string_literal: true

module Admin
  module System
    # Manage public REST API keys (see Api::V1). The plaintext token is shown once,
    # at creation time, then only its prefix is displayed.
    class ApiKeysController < BaseController
      before_action -> { require_permission("system.settings.manage") }
      before_action :set_api_key, only: :revoke

      def index
        keys = Administration::ApiKey.order(created_at: :desc).limit(200)

        render inertia: "Admin/System/ApiKeys/Index", props: {
          title: t("mcweb.admin.api_keys.title"),
          subtitle: t("mcweb.admin.api_keys.subtitle"),
          newUrl: new_admin_system_api_key_path,
          keys: keys.map { |key| serialize_key(key) }
        }
      end

      def new
        render inertia: "Admin/System/ApiKeys/Form", props: {
          title: t("mcweb.admin.api_keys.form_new"),
          submitUrl: admin_system_api_keys_path,
          backUrl: admin_system_api_keys_path
        }
      end

      def create
        name = params.dig(:api_key, :name).to_s.strip
        scopes = Array(params.dig(:api_key, :scopes)).map(&:to_s)
        username = params.dig(:api_key, :username).to_s.strip
        user = username.present? ? User.find_by(username: username) : nil

        if name.blank?
          return redirect_to new_admin_system_api_key_path, alert: t("mcweb.admin.api_keys.name_required")
        end
        if scopes.empty? || (scopes - Administration::ApiKey::VALID_SCOPES).any?
          return redirect_to new_admin_system_api_key_path, alert: t("mcweb.admin.api_keys.scopes_invalid")
        end
        if username.present? && user.nil?
          return redirect_to new_admin_system_api_key_path, alert: t("mcweb.admin.api_keys.user_not_found")
        end
        if user && user != current_user && !current_user.account_owner?
          return redirect_to new_admin_system_api_key_path, alert: t("mcweb.admin.api_keys.user_binding_forbidden")
        end
        if user && (user.deleted? || user.banned?)
          return redirect_to new_admin_system_api_key_path, alert: t("mcweb.admin.api_keys.user_unavailable")
        end

        record, token = Administration::ApiKey.generate!(
          name: name, scopes: scopes, user: user, created_by: current_user
        )
        Administration::AuditLogger.call(
          actor: current_user, action: "admin.api_key_created", resource: record,
          metadata: { name: name, scopes: record.scopes }
        )
        redirect_to admin_system_api_keys_path,
                    notice: t("mcweb.admin.api_keys.created_with_token", token: token)
      end

      def revoke
        @api_key.revoke! unless @api_key.revoked?
        Administration::AuditLogger.call(
          actor: current_user, action: "admin.api_key_revoked", resource: @api_key,
          metadata: { name: @api_key.name }
        )
        redirect_to admin_system_api_keys_path, notice: t("mcweb.admin.api_keys.revoked")
      end

      private

      def set_api_key
        @api_key = Administration::ApiKey.find(params[:id])
      end

      def serialize_key(key)
        {
          id: key.id,
          name: key.name,
          prefix: key.token_prefix,
          scopes: key.scope_list,
          user: key.user&.username,
          lastUsedAt: key.last_used_at ? l(key.last_used_at, format: :short) : nil,
          revoked: key.revoked?,
          createdAt: l(key.created_at, format: :short),
          revokeUrl: revoke_admin_system_api_key_path(key)
        }
      end
    end
  end
end
