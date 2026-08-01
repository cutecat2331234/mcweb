# frozen_string_literal: true

module Administration
  class AuditActionLabel < ApplicationService
    TRANSLATION_PREFIX = "mcweb.audit.actions"

    def initialize(action, locale: I18n.locale)
      @action = action.to_s.strip
      @locale = locale
    end

    def call
      return I18n.t("mcweb.labels.not_available", locale: @locale) if @action.blank?

      translation_key = "#{TRANSLATION_PREFIX}.#{@action.tr('.', '_')}"
      return I18n.t(translation_key, locale: @locale) if I18n.exists?(translation_key, @locale)

      @action
        .split(".")
        .filter_map { |segment| segment.tr("_-", "  ").squish.presence&.humanize }
        .join(" · ")
        .presence || I18n.t("mcweb.labels.not_available", locale: @locale)
    end
  end
end
