# frozen_string_literal: true

module Community
  class SerializeUserFields < ApplicationService
    class << self
      def for(user:, viewer: nil, context: :profile)
        definitions = definitions_for(context)
        values = Community::UserFieldValue
          .where(user: user, forum_user_field_definition_id: definitions.map(&:id))
          .index_by(&:forum_user_field_definition_id)

        definitions.filter_map do |definition|
          next unless context.to_sym == :registration || visible?(definition, user: user, viewer: viewer)

          value = values[definition.id]
          {
            key: definition.key,
            label: definition.label,
            field_type: definition.field_type,
            description: definition.description,
            choices: definition.choice_list,
            value: display_value(definition, value&.value),
            raw_value: value&.value.to_s,
            required: definition.required?,
            editable: context.to_sym == :registration || editable?(definition, user: user, viewer: viewer)
          }
        end
      end

      def definitions_for(context)
        case context.to_sym
        when :registration
          Community::UserFieldDefinition.for_registration.ordered
        else
          Community::UserFieldDefinition.for_profile.ordered
        end
      end

      def visible?(definition, user:, viewer:)
        case definition.visibility
        when "public"
          true
        when "owner"
          viewer&.id == user.id || staff_viewer?(viewer)
        when "staff"
          staff_viewer?(viewer)
        else
          false
        end
      end

      def editable?(definition, user:, viewer:)
        return false unless definition.editable_by_user?
        return false unless viewer&.id == user.id

        true
      end

      def display_value(definition, raw)
        return nil if raw.blank?

        case definition.field_type
        when "checkbox"
          ActiveModel::Type::Boolean.new.cast(raw) ? I18n.t("mcweb.labels.yes") : I18n.t("mcweb.labels.no")
        else
          raw
        end
      end

      def staff_viewer?(viewer)
        viewer&.permission?("forum.users.warn") || viewer&.permission?("admin.access")
      end
    end
  end
end
