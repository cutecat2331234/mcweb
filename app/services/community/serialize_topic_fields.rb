# frozen_string_literal: true

module Community
  class SerializeTopicFields
    class << self
      def for_form(section:, user:, topic: nil)
        definitions = Community::TopicFieldDefinition.active.ordered.select do |definition|
          definition.applicable_to_section?(section) && definition.editable_by?(user)
        end
        values = value_map(topic, definitions)

        definitions.map do |definition|
          serialize_definition(definition).merge(
            raw_value: values[definition.id]&.value,
            editable: true
          )
        end
      end

      def for_display(topic:, definitions: nil)
        definitions = Array(definitions || Community::TopicFieldDefinition.active.ordered).select do |definition|
          definition.applicable_to_section?(topic.section)
        end
        values = value_map(topic, definitions)

        definitions.filter_map do |definition|
          value = values[definition.id]&.value
          next if value.blank?

          serialize_definition(definition).merge(
            raw_value: value,
            value: value,
            display_value: display_value(definition, value)
          )
        end
      end

      def for_topic(topic:, user:)
        definitions = Community::TopicFieldDefinition.active.ordered.select do |definition|
          definition.applicable_to_section?(topic.section)
        end
        values = value_map(topic, definitions)

        definitions.map do |definition|
          value = values[definition.id]&.value
          serialize_definition(definition).merge(
            raw_value: value,
            value: value,
            display_value: value.present? ? display_value(definition, value) : nil,
            editable: definition.editable_by?(user)
          )
        end
      end

      private

      def value_map(topic, definitions)
        return {} unless topic&.persisted? && definitions.any?

        if topic.association(:topic_field_values).loaded?
          definition_ids = definitions.index_by(&:id)
          return topic.topic_field_values
            .select { |value| definition_ids.key?(value.forum_topic_field_definition_id) }
            .index_by(&:forum_topic_field_definition_id)
        end

        Community::TopicFieldValue
          .where(topic: topic, definition: definitions)
          .index_by(&:forum_topic_field_definition_id)
      end

      def serialize_definition(definition)
        {
          key: definition.key,
          label: definition.label,
          field_type: definition.field_type,
          description: definition.description.presence,
          choices: definition.choice_list,
          required: definition.required?,
          display_location: definition.display_location,
          owner_plugin_id: definition.owner_plugin_id
        }
      end

      def display_value(definition, value)
        definition.field_type == "checkbox" ? value == "1" : value
      end
    end
  end
end
