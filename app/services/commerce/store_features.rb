# frozen_string_literal: true

module Commerce
  class StoreFeatures
    Definition = Data.define(:id, :key, :label, :description, :default)

    DEFINITIONS = [
      Definition.new(
        id: :physical_products,
        key: "store.features.physical_products",
        label: "实体商品",
        description: "允许创建 physical 类型商品及 requires_shipping 字段",
        default: false
      ),
      Definition.new(
        id: :shipping,
        key: "store.features.shipping",
        label: "物流配送",
        description: "结账收货地址、配送方式、运费计算与用户地址簿",
        default: false
      ),
      Definition.new(
        id: :gift_wrap,
        key: "store.features.gift_wrap",
        label: "礼品包装",
        description: "结账页礼品包装选项与费用",
        default: false
      ),
      Definition.new(
        id: :order_shipping_management,
        key: "store.features.order_shipping_management",
        label: "订单物流管理",
        description: "后台填写快递单号、标记发货与装箱单",
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

        DEFINITIONS.each do |definition|
          next unless permitted.key?(definition.id.to_s)

          enabled = ActiveModel::Type::Boolean.new.cast(permitted[definition.id.to_s])
          SiteSetting.set(definition.key, enabled ? "true" : "false")
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
          label: I18n.t("mcweb.store_features.#{definition.id}.label", default: definition.label),
          description: I18n.t("mcweb.store_features.#{definition.id}.description", default: definition.description),
          enabled: enabled?(definition.id)
        }
      end

      def truthy?(value)
        value.to_s.in?(%w[true 1])
      end
    end
  end
end
