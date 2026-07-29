# frozen_string_literal: true

module Admin
  module Store
    class UserEntitlementsController < BaseController
      before_action -> { require_permission("store.entitlements.read") }, only: %i[index show]
      before_action -> { require_permission("store.entitlements.grant") }, only: %i[new create authorize_grant]
      before_action -> { require_permission("store.entitlements.revoke") },
        only: %i[revoke authorize_revoke]
      before_action :set_entitlement, only: %i[show revoke authorize_revoke]

      def index
        scope = ::Commerce::UserEntitlement
          .includes(:user, :product)
          .order(created_at: :desc)
        scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?
        scope = scope.where(store_product_id: params[:product_id]) if params[:product_id].present?
        if params[:status] == "active"
          scope = scope.currently_active
        elsif params[:status] == "revoked"
          scope = scope.where.not(revoked_at: nil)
        end

        @pagy, entitlements = pagy(:offset, scope, limit: 50)
        render inertia: "Admin/Generic/Index", props: {
          title: t("mcweb.admin.store.user_entitlements.title"),
          columns: [
            admin_column(:user, t("mcweb.admin.store.user_entitlements.col_user"), link: true),
            admin_column(:product, t("mcweb.admin.store.user_entitlements.col_product")),
            admin_column(:status, t("mcweb.admin.store.user_entitlements.col_status")),
            admin_column(:expires_at, t("mcweb.admin.store.user_entitlements.col_expires_at"))
          ],
          rows: entitlements.map do |entitlement|
            admin_row(
              user: entitlement.user.username,
              product: entitlement.product.name,
              status: entitlement_status_label(entitlement),
              expires_at: entitlement_expires_label(entitlement),
              url: admin_store_user_entitlement_path(entitlement)
            )
          end,
          pagination: pagy_props(@pagy),
          statusTabs: entitlement_status_tabs,
          actions: current_user.permission?("store.entitlements.grant") ? [
            {
              label: t("mcweb.admin.store.user_entitlements.grant"),
              href: new_admin_store_user_entitlement_path
            }
          ] : []
        }
      end

      def show
        render inertia: "Admin/Generic/Show", props: {
          title: "#{@entitlement.user.username} · #{@entitlement.product.name}",
          fields: [
            { label: t("mcweb.admin.store.user_entitlements.field_user"), value: @entitlement.user.username },
            { label: t("mcweb.admin.store.user_entitlements.field_product"), value: @entitlement.product.name },
            { label: t("mcweb.admin.store.user_entitlements.field_status"), value: entitlement_status_label(@entitlement) },
            { label: t("mcweb.admin.store.user_entitlements.field_starts_at"), value: l(@entitlement.starts_at, format: :short) },
            { label: t("mcweb.admin.store.user_entitlements.field_expires_at"), value: entitlement_expires_label(@entitlement) }
          ],
          backUrl: admin_store_user_entitlements_path,
          highRiskActions: @entitlement.currently_active? &&
            current_user.permission?("store.entitlements.revoke") ? [
              {
                key: "entitlement_revoke",
                label: t("mcweb.admin.store.user_entitlements.action_revoke"),
                title: t("mcweb.admin.store.user_entitlements.revoke_title"),
                authorization_url: authorize_revoke_admin_store_user_entitlement_path(@entitlement),
                action_url: revoke_admin_store_user_entitlement_path(@entitlement),
                method: "post"
              }
            ] : []
        }
      end

      def new
        render inertia: "Admin/Store/UserEntitlements/Form", props: form_props
      end

      def authorize_grant
        result = entitlement_action("entitlement.grant").authorize
        return render_service_error(result) if result.failure?

        response.set_header("Cache-Control", "no-store")
        render json: authorization_json(result)
      end

      def create
        result = entitlement_action("entitlement.grant").call
        return render_service_error(result) if result.failure?

        render json: {
          request_id: result.value[:request_id],
          idempotent: result.value[:idempotent],
          redirect_url: admin_store_user_entitlement_path(result.value[:entitlement]),
          message: t("mcweb.flash.entitlement_granted")
        }
      end

      def authorize_revoke
        result = entitlement_action("entitlement.revoke").authorize
        return render_service_error(result) if result.failure?

        response.set_header("Cache-Control", "no-store")
        render json: authorization_json(result)
      end

      def revoke
        result = entitlement_action("entitlement.revoke").call
        return render_service_error(result) if result.failure?

        render json: {
          request_id: result.value[:request_id],
          idempotent: result.value[:idempotent],
          redirect_url: admin_store_user_entitlements_path,
          message: t("mcweb.flash.entitlement_revoked")
        }
      end

      private

      def set_entitlement
        @entitlement = ::Commerce::UserEntitlement.includes(:user, :product).find(params[:id])
      end

      def form_props
        {
          title: t("mcweb.admin.store.user_entitlements.grant_title"),
          products: entitlement_products.map do |product|
            {
              id: product.id,
              name: product.name,
              duration: entitlement_duration_label(product)
            }
          end,
          submitUrl: admin_store_user_entitlements_path,
          authorizationUrl: authorize_grant_admin_store_user_entitlements_path,
          backUrl: admin_store_user_entitlements_path
        }
      end

      def entitlement_products
        ::Commerce::Product.order(:name).select do |product|
          config = product.fulfillment_config.to_h.with_indifferent_access
          ActiveModel::Type::Boolean.new.cast(config[:entitlement_permanent]) ||
            config[:entitlement_days].to_i.positive?
        end
      end

      def entitlement_duration_label(product)
        config = product.fulfillment_config.to_h.with_indifferent_access
        if ActiveModel::Type::Boolean.new.cast(config[:entitlement_permanent])
          t("commerce.memberships.permanent")
        else
          t("mcweb.admin.store.user_entitlements.duration_days", count: config[:entitlement_days].to_i)
        end
      end

      def entitlement_action(action)
        if action == "entitlement.grant"
          user = User.find_by(username: params.dig(:user_entitlement, :username).to_s.strip)
          product = ::Commerce::Product.find_by(id: params.dig(:user_entitlement, :product_id))
        else
          user = @entitlement.user
          product = @entitlement.product
        end

        Commerce::HighRiskEntitlementAction.new(
          actor: current_user,
          action: action,
          user: user,
          product: product,
          entitlement: @entitlement,
          request_id: params[:request_id],
          reason: params[:reason],
          authorization_token: params[:authorization_token],
          confirmation: params[:confirmation],
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )
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
          preview_items: entitlement_preview_items(preview, target)
        }
      end

      def entitlement_preview_items(preview, target)
        items = [
          { label: t("mcweb.admin.high_risk.target_user"), value: target[:username] },
          { label: t("mcweb.admin.high_risk.product"), value: target[:product] }
        ]
        if preview[:action] == "entitlement.grant"
          items << {
            label: t("mcweb.admin.high_risk.current_count"),
            value: preview.dig(:before, :active_entitlement_count).to_s
          }
          items << {
            label: t("mcweb.admin.high_risk.result_count"),
            value: preview.dig(:after, :active_entitlement_count).to_s
          }
          items << {
            label: t("mcweb.admin.high_risk.expires_at"),
            value: preview.dig(:after, :expires_at).presence ||
              t("commerce.memberships.permanent")
          }
        else
          items << {
            label: t("mcweb.admin.high_risk.status_change"),
            value: t("mcweb.admin.store.user_entitlements.status_active_to_revoked")
          }
        end
        items
      end

      def entitlement_status_label(entitlement)
        if entitlement.revoked_at?
          t("mcweb.admin.store.user_entitlements.status_revoked")
        elsif entitlement.currently_active?
          t("mcweb.admin.store.user_entitlements.status_active")
        else
          t("mcweb.admin.store.user_entitlements.status_expired")
        end
      end

      def entitlement_expires_label(entitlement)
        entitlement.expires_at ? l(entitlement.expires_at, format: :short) :
          t("commerce.memberships.permanent")
      end

      def entitlement_status_tabs
        current = params[:status].to_s
        base = params.permit(:product_id).to_h
        [
          {
            label: t("mcweb.admin.store.user_entitlements.filter_all"),
            href: admin_store_user_entitlements_path(base),
            active: current.blank?
          },
          {
            label: t("mcweb.admin.store.user_entitlements.status_active"),
            href: admin_store_user_entitlements_path(base.merge(status: "active")),
            active: current == "active"
          },
          {
            label: t("mcweb.admin.store.user_entitlements.status_revoked"),
            href: admin_store_user_entitlements_path(base.merge(status: "revoked")),
            active: current == "revoked"
          }
        ]
      end

      def render_service_error(result)
        render json: { error: service_error_message(result) },
          status: service_error_status(result)
      end
    end
  end
end
