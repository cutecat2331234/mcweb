# frozen_string_literal: true

module Admin
  module Forum
    class BaseController < Admin::BaseController
      before_action -> { require_admin_module!("forum") }

      private

      def forum_t(key, **options)
        I18n.t("mcweb.admin.forum.#{key}", **options)
      end

      def forum_yes_no(value)
        value ? t("mcweb.labels.yes") : t("mcweb.labels.no")
      end

      def forum_na
        t("mcweb.labels.not_available")
      end

      def forum_list_join(items)
        Array(items).join(I18n.t("mcweb.commerce.list_separator"))
      end

      def section_notification_label(level)
        forum_t("sections.notification_#{level}", default: I18n.t("mcweb.forum.subscription_levels.#{level}"))
      end

      def forum_permission_label(roles)
        roles.present? ? Array(roles).join(", ") : forum_t("sections.permission_everyone")
      end

      def grant_rule_label(rule)
        I18n.t("mcweb.forum.badges.#{rule}", default: rule.to_s.humanize)
      end
    end
  end
end
