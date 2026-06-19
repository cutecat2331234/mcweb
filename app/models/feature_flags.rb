# frozen_string_literal: true

class FeatureFlags
  Definition = Data.define(:id, :key, :label, :description, :default, :path_prefixes)

  DEFINITIONS = [
    Definition.new(
      id: :forum,
      key: "features.forum.enabled",
      label: "论坛",
      description: "社区论坛、私信、通知及相关导航入口",
      default: true,
      path_prefixes: [ "/app/forum" ]
    ),
    Definition.new(
      id: :store,
      key: "features.store.enabled",
      label: "商城",
      description: "商品、购物车、订单及相关导航入口",
      default: true,
      path_prefixes: [ "/app/store" ]
    ),
    Definition.new(
      id: :website_blog,
      key: "features.website_blog.enabled",
      label: "官网博客",
      description: "官网导航与页脚中的「动态 / 博客」入口",
      default: true,
      path_prefixes: [ "/blog" ]
    ),
    Definition.new(
      id: :minecraft,
      key: "features.minecraft.enabled",
      label: "Minecraft 绑定",
      description: "玩家 Minecraft 账号绑定页面",
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
          label: definition.label,
          description: definition.description,
          enabled: enabled?(definition.id)
        }
      end
    end

    def update_from_params!(raw_params)
      permitted = raw_params.respond_to?(:permit) ? raw_params.permit(*DEFINITIONS.map { |d| d.id.to_s }) : raw_params.to_h
      states = proposed_states(permitted)

      if !states[:forum] && !states[:store]
        return ServiceResult.failure(error: "论坛和商城至少需要保留一个开启。")
      end

      DEFINITIONS.each do |definition|
        next unless permitted.key?(definition.id.to_s)

        enabled = ActiveModel::Type::Boolean.new.cast(permitted[definition.id.to_s])
        SiteSetting.set(definition.key, enabled ? "true" : "false")
      end

      ServiceResult.success(true)
    end

    def proposed_states(permitted)
      DEFINITIONS.to_h do |definition|
        key = definition.id.to_s
        value = if permitted.key?(key)
          ActiveModel::Type::Boolean.new.cast(permitted[key])
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
      label = definition&.label || "该功能"
      "#{label}已被管理员关闭。"
    end

    private

    def truthy?(value)
      value.to_s.in?(%w[true 1])
    end
  end
end
