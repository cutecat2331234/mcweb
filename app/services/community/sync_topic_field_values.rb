# frozen_string_literal: true

module Community
  class SyncTopicFieldValues < ApplicationService
    def initialize(topic:, user:, values:, require_required: true)
      @topic = topic
      @user = user
      @values = normalize_hash(values)
      @require_required = require_required
    end

    def call
      unless @user && Community::ForumAccess.topic_visible?(topic: @topic, user: @user)
        return ServiceResult.failure(error: "Topic not available.")
      end

      return ServiceResult.failure(error: "This topic is archived.") if @topic.archived_at.present?
      unless Community::SectionModeration.can_edit_topic?(user: @user, topic: @topic)
        return ServiceResult.failure(error: "You cannot edit this topic.")
      end

      definitions = editable_definitions
      existing = Community::TopicFieldValue
        .where(topic: @topic, definition: definitions)
        .index_by(&:forum_topic_field_definition_id)
      prepared = {}
      errors = {}

      definitions.each do |definition|
        submitted = @values.key?(definition.key)
        current = existing[definition.id]&.value
        final_value = submitted ? Community::TopicFieldValueRules.normalize(definition, @values[definition.key]) : current

        if @require_required && definition.required? &&
            Community::TopicFieldValueRules.blank_for_requirement?(definition, final_value)
          errors["custom_fields.#{definition.key}"] = Community::TopicFieldValueRules.required_error(definition)
          next
        end

        next unless submitted

        if final_value.blank? && definition.field_type != "checkbox"
          prepared[definition] = nil
          next
        end

        validation_error = Community::TopicFieldValueRules.error_for(definition, @values[definition.key])
        if validation_error
          errors["custom_fields.#{definition.key}"] = validation_error
        else
          prepared[definition] = final_value
        end
      end

      return ServiceResult.failure(errors: errors) if errors.any?

      changed_keys = persist(prepared, existing)
      publish_after_commit(changed_keys) if changed_keys.any?
      ServiceResult.success(topic: @topic, changed_keys: changed_keys)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def editable_definitions
      Community::TopicFieldDefinition.active.ordered.select do |definition|
        definition.applicable_to_section?(@topic.section) && definition.editable_by?(@user)
      end
    end

    def normalize_hash(values)
      raw = values.respond_to?(:to_unsafe_h) ? values.to_unsafe_h : values
      raw.is_a?(Hash) ? raw.stringify_keys : {}
    end

    def persist(prepared, existing)
      changed_keys = []
      Community::TopicFieldValue.transaction do
        prepared.each do |definition, value|
          record = existing[definition.id]
          next if record&.value == value

          if value.nil?
            record&.destroy!
          else
            record ||= Community::TopicFieldValue.new(topic: @topic, definition: definition)
            record.update!(value: value)
          end
          changed_keys << definition.key
        end
      end
      @topic.association(:topic_field_values).reset if changed_keys.any?
      changed_keys
    end

    def publish_after_commit(changed_keys)
      topic = @topic
      keys = changed_keys.freeze
      ActiveRecord.after_all_transactions_commit do
        Mcweb::Events.publish("forum.topic.fields.updated", topic: topic, field_keys: keys)
      end
    end
  end
end
