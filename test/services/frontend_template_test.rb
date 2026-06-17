# frozen_string_literal: true

require "test_helper"
require "zip"

class FrontendTemplateArchiveTest < ActiveSupport::TestCase
  setup do
    Frontend::Template.delete_all
    Frontend::TemplateStorage.ensure_root!
    FileUtils.rm_rf(Frontend::TemplateStorage.root)
    Frontend::TemplateStorage.ensure_root!
  end

  test "installs valid starter template archive" do
    zip = build_template_zip(
      key: "starter-test",
      extra_files: {},
      scopes: %w[website portal]
    )

    result = Frontend::InstallTemplateArchive.call(archive_io: StringIO.new(zip))
    assert result.success?, result.error
    template = result.value
    assert_equal "installed", template.status
    assert_predicate Frontend::TemplateStorage.path_for("starter-test").join("manifest.json"), :exist?
  end

  test "rejects javascript files in archive" do
    zip = build_template_zip(key: "evil-js", extra_files: { "app.js" => "alert(1)" })
    result = Frontend::ValidateTemplateArchive.call(archive_io: StringIO.new(zip))
    assert result.failure?
    assert_includes result.error, "不允许"
  end

  test "rejects admin paths in archive" do
    zip = build_template_zip(key: "evil-admin", extra_files: { "pages/Admin/hack.html" => "<p>x</p>" })
    result = Frontend::ValidateTemplateArchive.call(archive_io: StringIO.new(zip))
    assert result.failure?
    assert_includes result.error, "非法路径"
  end

  test "sanitizes script tags from slots" do
    result = Frontend::SanitizeTemplateSlot.call('<p>Hi</p><script>alert(1)</script>')
    assert_equal "<p>Hi</p>", result.value
  end

  test "activates template for website scope" do
    zip = build_template_zip(key: "activate-me", extra_files: {}, scopes: %w[website])
    Frontend::InstallTemplateArchive.call(archive_io: StringIO.new(zip))

    result = Frontend::ActivateTemplate.call(scope: "website", template_key: "activate-me")
    assert result.success?
    assert_equal "activate-me", Frontend::Template.active_key_for("website")
  end

  private

  def build_template_zip(key:, extra_files:, scopes: %w[website])
    manifest = {
      name: "Test #{key}",
      key: key,
      version: "1.0.0",
      scopes: scopes,
      tokens: { primary_color: "#ff0000" },
      assets: { css: [ "styles/theme.css" ] },
      slots: { website_footer: "slots/website_footer.html" }
    }

    buffer = Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry("manifest.json")
      zip.write manifest.to_json
      zip.put_next_entry("styles/theme.css")
      zip.write ".website-page { color: red; }"
      zip.put_next_entry("slots/website_footer.html")
      zip.write "<footer><p>Custom footer</p></footer>"
      extra_files.each do |path, content|
        zip.put_next_entry(path)
        zip.write content
      end
    end
    buffer.string
  end
end

class FrontendTemplateIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    grant_permission(@user, "website.templates.manage")
    grant_permission(@user, "admin.access")
    sign_in_as(@user)
    Frontend::Template.delete_all
    Frontend::TemplateStorage.ensure_root!
    FileUtils.rm_rf(Frontend::TemplateStorage.root)
    Frontend::TemplateStorage.ensure_root!
  end

  test "admin dashboard does not expose activeTemplate prop" do
    install_and_activate_template!
    get admin_root_path
    assert_response :success
    refute_includes response.body, "activeTemplate"
  end

  test "website home exposes activeTemplate when activated" do
    install_and_activate_template!
    get root_path
    assert_response :success
    assert_includes response.body, "activeTemplate"
    assert_includes response.body, "template-test"
  end

  test "theme asset route serves css" do
    install_and_activate_template!
    get frontend_theme_asset_path(template_key: "template-test", path: "styles/theme.css")
    assert_response :success
    assert_includes response.body, "color: red"
  end

  test "theme asset route blocks path traversal" do
    install_and_activate_template!
    get "/theme-assets/template-test/%2e%2e/secret.css"
    assert_response :not_found
  end

  test "admin templates index renders for authorized user" do
    get admin_frontend_templates_path
    assert_response :success
    assert_includes response.body, "Admin/Frontend/Templates/Index"
  end

  private

  def install_and_activate_template!
    zip = Zip::OutputStream.write_buffer do |out|
      out.put_next_entry("manifest.json")
      out.write({
        name: "Template Test",
        key: "template-test",
        version: "1.0.0",
        scopes: %w[website portal],
        assets: { css: [ "styles/theme.css" ] },
        slots: {}
      }.to_json)
      out.put_next_entry("styles/theme.css")
      out.write ".website-page { color: red; }"
    end.string

    Frontend::InstallTemplateArchive.call(archive_io: StringIO.new(zip))
    Frontend::ActivateTemplate.call(scope: "website", template_key: "template-test")
    Frontend::ActivateTemplate.call(scope: "portal", template_key: "template-test")
  end
end
