# frozen_string_literal: true

module Admin
  class BaseController < ApplicationController
    inertia_config layout: "inertia_admin"

    before_action :require_admin_access!

    private

    def require_admin_access!
      require_login
      return if performed?

      unless current_user.can_access_admin?
        redirect_to root_path, alert: t("mcweb.flash.admin_access_denied")
        return
      end

      unless current_user.permission?("admin.access")
        redirect_to root_path, alert: t("mcweb.flash.permission_denied")
      end
    end

    def require_admin_module!(module_key)
      return if current_user.admin_module_allowed?(module_key)

      redirect_to admin_root_path, alert: t("mcweb.flash.admin_module_denied")
      false
    end

    def product_type_label(type)
      return t("mcweb.labels.not_available") if type.blank?

      t("mcweb.labels.product_types.#{type}", default: type.to_s.humanize)
    end

    def product_status_label(status)
      return t("mcweb.labels.not_available") if status.blank?

      t("mcweb.labels.product_status.#{status}", default: status.to_s.humanize)
    end

    def prerequisite_match_mode_label(mode)
      return t("mcweb.labels.not_available") if mode.blank?

      t("mcweb.labels.prerequisite_match_mode.#{mode}", default: mode.to_s.humanize)
    end

    def enabled_disabled_label(active)
      active ? t("mcweb.labels.enabled") : t("mcweb.labels.disabled")
    end

    def gift_card_status_label(active)
      t("mcweb.labels.gift_card_status.#{active ? 'active' : 'inactive'}")
    end

    def fulfillment_status_label(status)
      return t("mcweb.labels.not_available") if status.blank?

      t("mcweb.labels.fulfillment_status.#{status}", default: status.to_s.humanize)
    end

    def refund_status_label(status)
      return t("mcweb.labels.not_available") if status.blank?

      t("mcweb.labels.refund_status.#{status}", default: status.to_s.humanize)
    end

    def webhook_delivery_status_label(status)
      return t("mcweb.labels.not_available") if status.blank?

      t("mcweb.labels.webhook_delivery_status.#{status}", default: status.to_s.humanize)
    end

    def review_status_label(status)
      return t("mcweb.labels.not_available") if status.blank?

      t("mcweb.labels.review_status.#{status}", default: status.to_s.humanize)
    end

    def order_status_label(status)
      return t("mcweb.labels.not_available") if status.blank?

      t("mcweb.labels.order_status.#{status}", default: status.to_s.humanize)
    end
  end
end
