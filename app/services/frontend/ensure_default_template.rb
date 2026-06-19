# frozen_string_literal: true

module Frontend
  class EnsureDefaultTemplate < ApplicationService
    BUILTIN_KEY = "mcweb-default"
    STARTER_ARCHIVE = Rails.root.join("public/template-starter/starter.zip")

    def call
      template = ::Frontend::Template.find_by(key: BUILTIN_KEY)
      if template&.installed?
        activate_if_missing!
        return ServiceResult.success(template)
      end

      return ServiceResult.failure(error: "缺少内置模板包：#{STARTER_ARCHIVE}") unless STARTER_ARCHIVE.exist?

      File.open(STARTER_ARCHIVE, "rb") do |io|
        result = InstallTemplateArchive.call(
          archive_io: io,
          actor: nil,
          key_override: BUILTIN_KEY,
          manifest_overrides: {
            "name" => "McWeb 内置默认",
            "builtin" => true
          }
        )
        return result unless result.success?

        activate_if_missing!
        ServiceResult.success(result.value)
      end
    end

    private

    def activate_if_missing!
      %w[website portal].each do |scope|
        next if ::Frontend::Template.active_key_for(scope).present?

        ActivateTemplate.call(scope: scope, template_key: BUILTIN_KEY, actor: nil)
      end
    end
  end
end
