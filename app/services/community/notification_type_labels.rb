# frozen_string_literal: true

module Community
  module NotificationTypeLabels
    def self.label_for(type)
      type_key = type.to_s
      labels = I18n.t("mcweb.labels.notification_types", default: {})
      return type_key.humanize unless labels.is_a?(Hash) && labels.present?

      label = labels[type_key.to_sym] || labels[type_key]
      label.presence || type_key.humanize
    end
  end
end
