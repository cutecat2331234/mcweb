# frozen_string_literal: true

module Mcweb
  module LocaleResolver
    module_function

    ALIASES = {
      "zh" => "zh-CN",
      "zh-cn" => "zh-CN",
      "zh-hans" => "zh-CN",
      "en" => "en",
      "en-us" => "en",
      "en-gb" => "en"
    }.freeze

    def normalize(value)
      return nil if value.blank?

      candidate = value.to_s.tr("_", "-")
      ALIASES[candidate.downcase] ||
        available_locales.find { |locale| locale.casecmp?(candidate) }
    end

    def resolve(value, fallback: I18n.default_locale)
      normalize(value) || normalize(fallback) || available_locales.first
    end

    def available_locales
      I18n.available_locales.map(&:to_s)
    end
  end
end
