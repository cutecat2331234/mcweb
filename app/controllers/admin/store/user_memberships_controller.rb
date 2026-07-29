# frozen_string_literal: true

module Admin
  module Store
    class UserMembershipsController < BaseController
      before_action -> { require_permission("store.entitlements.read") }, only: %i[index show]
      before_action -> { require_permission("store.entitlements.grant") }, only: %i[new create authorize_grant]
      before_action -> { require_permission("store.entitlements.revoke") },
        only: %i[destroy revoke authorize_revoke]
      before_action :set_membership, only: %i[show destroy revoke authorize_revoke]

      def index
        scope = ::Commerce::UserMembership.includes(:user, :membership_type).order(created_at: :desc)
        scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?
        scope = scope.where(store_membership_type_id: params[:membership_type_id]) if params[:membership_type_id].present?
        scope = scope.where(status: params[:status]) if params[:status].present?

        @pagy, memberships = pagy(:offset, scope, limit: 50)

        render inertia: "Admin/Generic/Index", props: {
          title: t("mcweb.admin.store.user_memberships.title"),
          columns: [
            admin_column(:user, t("mcweb.admin.store.user_memberships.col_user"), link: true),
            admin_column(:type, t("mcweb.admin.store.user_memberships.col_type")),
            admin_column(:status, t("mcweb.admin.store.user_memberships.col_status")),
            admin_column(:expires_at, t("mcweb.admin.store.user_memberships.col_expires_at"))
          ],
          rows: memberships.map do |membership|
            admin_row(
              user: membership.user.username,
              type: membership.membership_type.name,
              status: membership_status_label(membership.status),
              expires_at: membership_expires_label(membership),
              url: admin_store_user_membership_path(membership)
            )
          end,
          pagination: pagy_props(@pagy),
          statusTabs: membership_status_tabs,
          kindTabs: membership_type_tabs,
          actions: current_user.permission?("store.entitlements.grant") ? [
            { label: t("mcweb.admin.store.user_memberships.grant"), href: new_admin_store_user_membership_path }
          ] : []
        }
      end

      def show
        render inertia: "Admin/Generic/Show", props: {
          title: "#{@membership.user.username} · #{@membership.membership_type.name}",
          fields: [
            { label: t("mcweb.admin.store.user_memberships.field_user"), value: @membership.user.username },
            { label: t("mcweb.admin.store.user_memberships.field_type"), value: @membership.membership_type.name },
            { label: t("mcweb.admin.store.user_memberships.field_status"), value: membership_status_label(@membership.status) },
            { label: t("mcweb.admin.store.user_memberships.field_starts_at"), value: l(@membership.starts_at, format: :short) },
            { label: t("mcweb.admin.store.user_memberships.field_expires_at"), value: membership_expires_label(@membership) },
            { label: t("mcweb.admin.store.user_memberships.field_source"), value: membership_source_label(@membership.source) }
          ],
          backUrl: admin_store_user_memberships_path,
          highRiskActions: @membership.active? && current_user.permission?("store.entitlements.revoke") ? [
            {
              key: "membership_revoke",
              label: t("mcweb.admin.store.user_memberships.action_revoke"),
              title: t("mcweb.admin.store.user_memberships.revoke_title"),
              authorization_url: authorize_revoke_admin_store_user_membership_path(@membership),
              action_url: revoke_admin_store_user_membership_path(@membership),
              method: "post"
            }
          ] : []
        }
      end

      def new
        render inertia: "Admin/Store/UserMemberships/Form", props: form_props
      end

      def create
        result = membership_action("membership.grant").call
        return render_service_error(result) if result.failure?

        render json: {
          request_id: result.value[:request_id],
          idempotent: result.value[:idempotent],
          redirect_url: admin_store_user_membership_path(result.value[:membership]),
          message: t("mcweb.flash.membership_granted")
        }
      end

      def authorize_grant
        result = membership_action("membership.grant").authorize
        return render_service_error(result) if result.failure?

        response.set_header("Cache-Control", "no-store")
        render json: authorization_json(result)
      end

      def destroy
        execute_revoke
      end

      def revoke
        execute_revoke
      end

      def authorize_revoke
        result = membership_action("membership.revoke").authorize
        return render_service_error(result) if result.failure?

        response.set_header("Cache-Control", "no-store")
        render json: authorization_json(result)
      end

      private

      def set_membership
        @membership = ::Commerce::UserMembership.includes(:user, :membership_type).find(params[:id])
      end

      def form_props
        {
          title: t("mcweb.admin.store.user_memberships.grant_title"),
          membership_types: ::Commerce::MembershipType.active_types.by_display_priority.map { |type| { id: type.id, name: type.name } },
          submitUrl: admin_store_user_memberships_path,
          authorizationUrl: authorize_grant_admin_store_user_memberships_path,
          backUrl: admin_store_user_memberships_path
        }
      end

      def membership_action(action)
        if action == "membership.grant"
          user = User.find_by(username: params.dig(:user_membership, :username).to_s.strip)
          membership_type = ::Commerce::MembershipType.find_by(
            id: params.dig(:user_membership, :membership_type_id)
          )
        else
          user = @membership.user
          membership_type = @membership.membership_type
        end

        Commerce::HighRiskMembershipAction.new(
          actor: current_user,
          action: action,
          user: user,
          membership_type: membership_type,
          membership: @membership,
          grant_game_permissions: params.dig(:user_membership, :grant_game_permissions),
          revoke_game_permissions: params.fetch(:revoke_game_permissions, true),
          request_id: params[:request_id],
          reason: params[:reason],
          authorization_token: params[:authorization_token],
          confirmation: params[:confirmation],
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )
      end

      def execute_revoke
        result = membership_action("membership.revoke").call
        return render_service_error(result) if result.failure?

        render json: {
          request_id: result.value[:request_id],
          idempotent: result.value[:idempotent],
          redirect_url: admin_store_user_memberships_path,
          message: t("mcweb.flash.membership_revoked")
        }
      end

      def authorization_json(result)
        value = result.value
        preview = value[:preview]
        target = value[:target]
        {
          authorization_token: value[:authorization_token],
          confirmation: value[:confirmation],
          request_id: value[:request_id],
          expires_in: value[:expires_in],
          preview_items: membership_preview_items(preview, target)
        }
      end

      def membership_preview_items(preview, target)
        items = [
          {
            label: t("mcweb.admin.high_risk.target_user"),
            value: target[:username]
          },
          {
            label: t("mcweb.admin.high_risk.membership_type"),
            value: target[:membership_type]
          }
        ]
        if preview[:action] == "membership.grant"
          items << {
            label: t("mcweb.admin.high_risk.current_count"),
            value: preview.dig(:before, :active_membership_count).to_s
          }
          items << {
            label: t("mcweb.admin.high_risk.result_count"),
            value: preview.dig(:after, :active_membership_count).to_s
          }
          items << {
            label: t("mcweb.admin.high_risk.expires_at"),
            value: preview.dig(:after, :expires_at).presence ||
              t("commerce.memberships.permanent")
          }
        else
          items << {
            label: t("mcweb.admin.high_risk.status_change"),
            value: "#{preview.dig(:before, :status)} → #{preview.dig(:after, :status)}"
          }
        end
        items
      end

      def render_service_error(result)
        render json: { error: service_error_message(result) },
          status: service_error_status(result)
      end

      def membership_status_label(status)
        t("mcweb.labels.membership_status.#{status}", default: status.to_s.humanize)
      end

      def membership_source_label(source)
        t("mcweb.labels.membership_source.#{source}", default: source.to_s.humanize)
      end

      def membership_expires_label(membership)
        membership.expires_at ? l(membership.expires_at, format: :short) : t("commerce.memberships.permanent")
      end

      def membership_status_tabs
        current = params[:status].to_s.presence
        [
          { label: t("mcweb.admin.store.user_memberships.filter_all"), href: admin_store_user_memberships_path(membership_index_params.except(:status)), active: current.blank? },
          *%w[active expired revoked].map do |status|
            {
              label: membership_status_label(status),
              href: admin_store_user_memberships_path(membership_index_params.merge(status: status)),
              active: current == status
            }
          end
        ]
      end

      def membership_type_tabs
        current_type = params[:membership_type_id].to_s.presence
        [
          {
            label: t("mcweb.admin.store.user_memberships.filter_all_types"),
            href: admin_store_user_memberships_path(membership_index_params.except(:membership_type_id)),
            active: current_type.blank?
          },
          *::Commerce::MembershipType.by_display_priority.map do |type|
            {
              label: type.name,
              href: admin_store_user_memberships_path(membership_index_params.merge(membership_type_id: type.id)),
              active: current_type == type.id.to_s
            }
          end
        ]
      end

      def membership_index_params
        {
          status: params[:status].presence,
          membership_type_id: params[:membership_type_id].presence
        }.compact
      end
    end
  end
end
