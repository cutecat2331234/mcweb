# frozen_string_literal: true

module Community
  module TopicFieldValueRules
    module_function

    TRUE_VALUES = [ true, 1, "1", "true", "on", "yes" ].freeze
    FALSE_VALUES = [ false, 0, "0", "false", "off", "no", nil, "" ].freeze

    def normalize(definition, raw)
      if definition.field_type == "checkbox"
        TRUE_VALUES.include?(raw) ? "1" : "0"
      else
        raw.to_s.strip
      end
    end

    def error_for(definition, raw)
      value = normalize(definition, raw)

      case definition.field_type
      when "number"
        return translated(:number, definition) unless value.match?(/\A-?(?:\d+(?:\.\d+)?|\.\d+)\z/)
      when "url"
        return translated(:url, definition) unless UrlSafety.http_https_url?(value)
      when "select"
        return translated(:invalid_choice, definition) unless definition.choice_list.include?(value)
      when "checkbox"
        return translated(:invalid_choice, definition) unless TRUE_VALUES.include?(raw) || FALSE_VALUES.include?(raw)
      end

      nil
    end

    def blank_for_requirement?(definition, value)
      value.blank? || (definition.field_type == "checkbox" && value != "1")
    end

    def required_error(definition)
      translated(:required, definition)
    end

    def translated(key, definition)
      I18n.t("mcweb.forum.user_fields.#{key}", label: definition.label)
    end
    private_class_method :translated
  end
end
