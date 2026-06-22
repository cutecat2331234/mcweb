# frozen_string_literal: true

module Admin
  module Store
    class UserMembershipsController < BaseController
      before_action -> { require_permission("store.products.manage") }

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
          actions: [ { label: t("mcweb.admin.store.user_memberships.grant"), href: new_admin_store_user_membership_path } ]
        }
      end

      def show
        membership = ::Commerce::UserMembership.includes(:user, :membership_type).find(params[:id])
        render inertia: "Admin/Generic/Show", props: {
          title: "#{membership.user.username} · #{membership.membership_type.name}",
          fields: [
            { label: t("mcweb.admin.store.user_memberships.field_user"), value: membership.user.username },
            { label: t("mcweb.admin.store.user_memberships.field_type"), value: membership.membership_type.name },
            { label: t("mcweb.admin.store.user_memberships.field_status"), value: membership_status_label(membership.status) },
            { label: t("mcweb.admin.store.user_memberships.field_starts_at"), value: l(membership.starts_at, format: :short) },
            { label: t("mcweb.admin.store.user_memberships.field_expires_at"), value: membership_expires_label(membership) },
            { label: t("mcweb.admin.store.user_memberships.field_source"), value: membership_source_label(membership.source) }
          ],
          backUrl: admin_store_user_memberships_path,
          actions: membership.active? ? [
            {
              label: t("mcweb.admin.store.user_memberships.action_revoke"),
              href: admin_store_user_membership_path(membership),
              method: "delete",
              confirm: t("mcweb.admin.store.user_memberships.confirm_revoke")
            }
          ] : []
        }
      end

      def new
        render inertia: "Admin/Store/UserMemberships/Form", props: form_props
      end

      def create
        user = User.find_by!(username: params.dig(:user_membership, :username))
        type = ::Commerce::MembershipType.find(params.dig(:user_membership, :membership_type_id))

        result = Commerce::GrantMembership.call(
          user: user,
          membership_type: type,
          source: "admin_grant",
          grant_game_permissions: ActiveModel::Type::Boolean.new.cast(params.dig(:user_membership, :grant_game_permissions))
        )

        if result.success?
          redirect_to admin_store_user_membership_path(result.value), notice: t("mcweb.flash.membership_granted")
        else
          redirect_to new_admin_store_user_membership_path, alert: service_error_message(result)
        end
      end

      def destroy
        membership = ::Commerce::UserMembership.find(params[:id])
        result = Commerce::RevokeMembership.call(membership: membership)
        if result.success?
          redirect_to admin_store_user_memberships_path, notice: t("mcweb.flash.membership_revoked")
        else
          redirect_to admin_store_user_membership_path(membership), alert: service_error_message(result)
        end
      end

      private

      def form_props
        {
          title: t("mcweb.admin.store.user_memberships.grant_title"),
          membership_types: ::Commerce::MembershipType.active_types.by_display_priority.map { |type| { id: type.id, name: type.name } },
          submitUrl: admin_store_user_memberships_path,
          backUrl: admin_store_user_memberships_path
        }
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
