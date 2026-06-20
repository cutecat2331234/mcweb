# frozen_string_literal: true

module Community
  class SyncUserFieldValues < ApplicationService
    def initialize(user:, values:, context: :profile)
      @user = user
      @values = values.is_a?(Hash) ? values.stringify_keys : {}
      @context = context
    end

    def call
      definitions = Community::SerializeUserFields.definitions_for(@context)
      errors = {}

      definitions.each do |definition|
        next unless definition.editable_by_user? || @context == :registration

        raw = @values[definition.key].to_s
        if definition.field_type == "checkbox"
          raw = ActiveModel::Type::Boolean.new.cast(@values[definition.key]) ? "1" : "0"
        end

        if definition.required? && raw.blank?
          errors[definition.key] = I18n.t("mcweb.forum.user_fields.required", label: definition.label)
          next
        end

        next if raw.blank? && !definition.required?

        validation_error = validate_value(definition, raw)
        if validation_error
          errors[definition.key] = validation_error
          next
        end

        record = Community::UserFieldValue.find_or_initialize_by(user: @user, definition: definition)
        record.value = normalize_value(definition, raw)
        record.save!
      end

      return ServiceResult.failure(errors: errors) if errors.any?

      ServiceResult.success
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def validate_value(definition, raw)
      case definition.field_type
      when "number"
        return I18n.t("mcweb.forum.user_fields.number", label: definition.label) unless raw.match?(/\A-?\d+(\.\d+)?\z/)
      when "url"
        return I18n.t("mcweb.forum.user_fields.url", label: definition.label) unless raw.match?(%r{\Ahttps?://}i)
      when "select"
        return I18n.t("mcweb.forum.user_fields.invalid_choice", label: definition.label) unless definition.choice_list.include?(raw)
      end

      nil
    end

    def normalize_value(definition, raw)
      case definition.field_type
      when "checkbox"
        ActiveModel::Type::Boolean.new.cast(raw) ? "1" : "0"
      else
        raw.strip
      end
    end
  end
end
