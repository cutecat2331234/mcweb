# frozen_string_literal: true

require "test_helper"

class FrontendActivateTemplateTest < ActiveSupport::TestCase
  setup do
    Frontend::Template.delete_all
    SiteSetting.where(key: %w[frontend.active_website_template frontend.active_portal_template]).delete_all
    skip "starter.zip missing" unless Rails.root.join("public/template-starter/starter.zip").exist?

    Frontend::EnsureDefaultTemplate.call
    @custom = build_and_install_custom_template!
    Frontend::ActivateTemplate.call(scope: "website", template_key: @custom.key)
  end

  test "deactivating custom template falls back to builtin" do
    result = Frontend::ActivateTemplate.call(scope: "website", template_key: nil)
    assert result.success?
    assert_equal Frontend::EnsureDefaultTemplate::BUILTIN_KEY, Frontend::Template.active_key_for("website")
  end

  private

  def build_and_install_custom_template!
    zip = Zip::OutputStream.write_buffer do |out|
      out.put_next_entry("manifest.json")
      out.write({
        name: "Custom Template",
        key: "custom-test",
        version: "1.0.0",
        scopes: %w[website portal],
        assets: { css: [ "styles/theme.css" ] },
        slots: {}
      }.to_json)
      out.put_next_entry("styles/theme.css")
      out.write ".website-page { color: blue; }"
    end.string

    Frontend::InstallTemplateArchive.call(archive_io: StringIO.new(zip)).value
  end
end
