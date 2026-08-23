# frozen_string_literal: true

class FeatureFlags
  Definition = Data.define(:id, :key, :label, :description, :default, :path_prefixes)

  DEFINITIONS = [
    Definition.new(
      id: :forum,
      key: "features.forum.enabled",
      label: "mcweb.user_copy.feature_forum_label",
      description: "mcweb.user_copy.feature_forum_description",
      default: true,
      path_prefixes: [ "/app/forum" ]
    ),
    Definition.new(
      id: :store,
      key: "features.store.enabled",
      label: "mcweb.user_copy.feature_store_label",
      description: "mcweb.user_copy.feature_store_description",
      default: true,
      path_prefixes: [ "/app/store" ]
    ),
    Definition.new(
      id: :website_blog,
      key: "features.website_blog.enabled",
      label: "mcweb.user_copy.feature_blog_label",
      description: "mcweb.user_copy.feature_blog_description",
      default: true,
      path_prefixes: [ "/blog" ]
    ),
    Definition.new(
      id: :minecraft,
      key: "features.minecraft.enabled",
      label: "mcweb.user_copy.feature_minecraft_label",
      description: "mcweb.user_copy.feature_minecraft_description",
      default: true,
      path_prefixes: [ "/app/minecraft/link" ]
    )
  ].freeze

  class << self
    def definitions
      DEFINITIONS
    end

    def definition_for(id)
      DEFINITIONS.find { |definition| definition.id == id.to_sym }
    end

    def enabled?(feature_id)
      definition = definition_for(feature_id)
      return true unless definition

      truthy?(SiteSetting.get(definition.key, definition.default ? "true" : "false"))
    end

    def frontend_hash
      DEFINITIONS.to_h { |definition| [ definition.id.to_s, enabled?(definition.id) ] }
    end

    def admin_props
      DEFINITIONS.map do |definition|
        {
          id: definition.id.to_s,
          label: I18n.t(definition.label),
          description: I18n.t(definition.description),
          enabled: enabled?(definition.id)
        }
      end
    end

    def update_from_params!(raw_params)
      permitted = raw_params.respond_to?(:permit) ? raw_params.permit(*DEFINITIONS.map { |d| d.id.to_s }) : raw_params.to_h
      states = proposed_states(permitted)

      if !states[:forum] && !states[:store]
        return ServiceResult.failure(error: :feature_portal_required)
      end

      updates = DEFINITIONS.each_with_object({}) do |definition, values|
        next unless permitted.key?(definition.id.to_s)

        values[definition.key] = normalized_value(definition, permitted[definition.id.to_s])
      end
      SiteSetting.transaction do
        updates.each { |key, value| SiteSetting.set(key, value) }
      end

      ServiceResult.success(true)
    end

    def proposed_states(permitted)
      DEFINITIONS.to_h do |definition|
        key = definition.id.to_s
        value = if permitted.key?(key)
          normalized_value(definition, permitted[key]) == "true"
        else
          enabled?(definition.id)
        end
        [ definition.id, value ]
      end
    end

    def feature_for_path(path)
      DEFINITIONS.find do |definition|
        definition.path_prefixes.any? { |prefix| path.start_with?(prefix) }
      end&.id
    end

    def primary_portal_path(helpers)
      return helpers.forum_sections_path if enabled?(:forum)
      return helpers.store_products_path if enabled?(:store)

      helpers.identity_sign_in_path
    end

    def disabled_message(feature_id)
      definition = definition_for(feature_id)
      label = if definition
        I18n.t(definition.label)
      else
        I18n.t("mcweb.user_copy.feature_generic_label")
      end
      I18n.t("mcweb.user_copy.feature_disabled_message", feature: label)
    end

    private

    def normalized_value(definition, value)
      Mcweb::SettingsNamespaceRegistry.normalize_for_write(
        definition.key,
        value,
        surface: :dedicated,
        owner: "admin.system.feature_toggles"
      )
    end

    def truthy?(value)
      value.to_s.in?(%w[true 1])
    end
  end
end
