# frozen_string_literal: true

module Commerce
  class StoreFeatures
    Definition = Data.define(:id, :key, :label, :description, :default)

    DEFINITIONS = [
      Definition.new(
        id: :physical_products,
        key: "store.features.physical_products",
        label: "mcweb.user_copy.store_feature_physical_label",
        description: "mcweb.user_copy.store_feature_physical_description",
        default: false
      ),
      Definition.new(
        id: :shipping,
        key: "store.features.shipping",
        label: "mcweb.user_copy.store_feature_shipping_label",
        description: "mcweb.user_copy.store_feature_shipping_description",
        default: false
      ),
      Definition.new(
        id: :gift_wrap,
        key: "store.features.gift_wrap",
        label: "mcweb.user_copy.store_feature_gift_wrap_label",
        description: "mcweb.user_copy.store_feature_gift_wrap_description",
        default: false
      ),
      Definition.new(
        id: :order_shipping_management,
        key: "store.features.order_shipping_management",
        label: "mcweb.user_copy.store_feature_order_shipping_label",
        description: "mcweb.user_copy.store_feature_order_shipping_description",
        default: false
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
        return false unless definition

        truthy?(SiteSetting.get(definition.key, definition.default ? "true" : "false"))
      end

      def frontend_hash
        DEFINITIONS.to_h { |definition| [ definition.id.to_s, enabled?(definition.id) ] }
      end

      def admin_props
        DEFINITIONS.map { |definition| localized_definition(definition) }
      end

      def update_from_params!(raw_params)
        permitted = raw_params.respond_to?(:permit) ? raw_params.permit(*DEFINITIONS.map { |d| d.id.to_s }) : raw_params.to_h

        normalized_updates = DEFINITIONS.each_with_object({}) do |definition, updates|
          next unless permitted.key?(definition.id.to_s)

          updates[definition.key] = Mcweb::SettingsNamespaceRegistry.normalize_for_write(
            definition.key,
            permitted[definition.id.to_s],
            surface: :dedicated,
            owner: "admin.store.settings"
          )
        end
        SiteSetting.transaction do
          normalized_updates.each do |key, value|
            SiteSetting.set(key, value)
          end
        end

        ServiceResult.success(true)
      end

      def product_visible?(product)
        return false if product.product_type == "physical" && !enabled?(:physical_products)
        return false if product.requires_shipping? && !enabled?(:shipping)

        true
      end

      def visible_products_scope(relation = Commerce::Product.all)
        scope = relation
        scope = scope.where.not(product_type: "physical") unless enabled?(:physical_products)
        unless enabled?(:shipping)
          scope = scope.where(requires_shipping: false)
          scope = scope.where.not(product_type: "physical")
        end
        scope
      end

      private

      def localized_definition(definition)
        {
          id: definition.id.to_s,
          label: I18n.t(definition.label),
          description: I18n.t(definition.description),
          enabled: enabled?(definition.id)
        }
      end

      def truthy?(value)
        value.to_s.in?(%w[true 1])
      end
    end
  end
end
