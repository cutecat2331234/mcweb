# frozen_string_literal: true

module Community
  class ValidateTopicFieldValues < ApplicationService
    def initialize(topic:, user:)
      @topic = topic
      @user = user
    end

    def call
      definitions = Community::TopicFieldDefinition.active.ordered.select do |definition|
        definition.applicable_to_section?(@topic.section) && definition.editable_by?(@user)
      end
      values = Community::TopicFieldValue
        .where(topic: @topic, definition: definitions)
        .index_by(&:forum_topic_field_definition_id)
      errors = {}

      definitions.each do |definition|
        raw = values[definition.id]&.value
        if definition.required? && Community::TopicFieldValueRules.blank_for_requirement?(definition, raw)
          errors["custom_fields.#{definition.key}"] = Community::TopicFieldValueRules.required_error(definition)
          next
        end
        next if raw.blank?

        validation_error = Community::TopicFieldValueRules.error_for(definition, raw)
        errors["custom_fields.#{definition.key}"] = validation_error if validation_error
      end

      errors.any? ? ServiceResult.failure(errors: errors) : ServiceResult.success
    end
  end
end
