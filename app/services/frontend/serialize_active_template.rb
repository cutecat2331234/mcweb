# frozen_string_literal: true

module Frontend
  class SerializeActiveTemplate < ApplicationService
    def initialize(template:, scope:)
      @template = template
      @scope = scope.to_s
    end

    def call
      manifest = @template.manifest.deep_stringify_keys
      assets = manifest.fetch("assets", {})
      slots = manifest.fetch("slots", {})

      ServiceResult.success(
        key: @template.key,
        name: @template.name,
        version: @template.version,
        scope: @scope,
        tokens: token_css_variables(manifest.fetch("tokens", {})),
        cssUrls: css_urls(assets),
        logoUrl: asset_url(assets["logo"]),
        faviconUrl: asset_url(assets["favicon"]),
        slots: slot_html(slots)
      )
    end

    private

    def token_css_variables(tokens)
      tokens.each_with_object({}) do |(name, value), memo|
        memo["--template-#{name.to_s.tr('_', '-')}"] = value.to_s
      end
    end

    def css_urls(assets)
      Array(assets["css"]).filter_map do |path|
        asset_url(path)
      end
    end

    def asset_url(path)
      return if path.blank?

      file = Pathname(@template.installed_path).join(path.to_s)
      cache_version = file.file? ? Digest::SHA256.file(file).hexdigest.first(12) : nil

      Frontend::BuildTemplateAssetUrl.call(
        template_key: @template.key,
        path: path,
        cache_version: cache_version
      )
    end

    def slot_html(slots)
      root = Pathname(@template.installed_path).cleanpath
      slots.each_with_object({}) do |(name, path), memo|
        file = root.join(path.to_s).cleanpath
        next unless file.file? && Frontend::PathContainment.within_root?(file, root)

        raw = file.read
        sanitized = Frontend::SanitizeTemplateSlot.call(raw).value
        memo[name.to_s] = sanitized
      end
    end
  end
end
