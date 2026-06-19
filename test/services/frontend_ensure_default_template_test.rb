# frozen_string_literal: true

require "test_helper"

class FrontendEnsureDefaultTemplateTest < ActiveSupport::TestCase
  setup do
    Frontend::Template.delete_all
    Frontend::TemplateStorage.ensure_root!
    FileUtils.rm_rf(Frontend::TemplateStorage.root)
    Frontend::TemplateStorage.ensure_root!
    SiteSetting.where(key: %w[frontend.active_website_template frontend.active_portal_template]).delete_all
  end

  test "installs builtin template from starter archive" do
    skip "starter.zip missing" unless Rails.root.join("public/template-starter/starter.zip").exist?

    result = Frontend::EnsureDefaultTemplate.call
    assert result.success?, result.error

    template = Frontend::Template.find_by!(key: Frontend::EnsureDefaultTemplate::BUILTIN_KEY)
    assert_equal "installed", template.status
    assert template.manifest["builtin"]
    assert_equal Frontend::EnsureDefaultTemplate::BUILTIN_KEY, Frontend::Template.active_key_for("website")
    assert_equal Frontend::EnsureDefaultTemplate::BUILTIN_KEY, Frontend::Template.active_key_for("portal")
  end

  test "builtin template cannot be deleted" do
    skip "starter.zip missing" unless Rails.root.join("public/template-starter/starter.zip").exist?

    Frontend::EnsureDefaultTemplate.call
    template = Frontend::Template.find_by!(key: Frontend::EnsureDefaultTemplate::BUILTIN_KEY)

    result = Frontend::DeleteTemplate.call(template: template)
    assert result.failure?
    assert_includes result.error, "内置"
    assert Frontend::Template.exists?(key: Frontend::EnsureDefaultTemplate::BUILTIN_KEY)
  end
end
