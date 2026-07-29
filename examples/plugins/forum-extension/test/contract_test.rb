# frozen_string_literal: true

require "test_helper"
require "mcweb/plugins/devtools"

class ForumExtensionReferencePluginContractTest < ActiveSupport::TestCase
  PLUGIN_ROOT = Pathname(__dir__).join("..").expand_path

  test "declares namespaced metadata moderation permission and a targeted UI action" do
    report = Mcweb::Plugins::Devtools::Validator.new(path: PLUGIN_ROOT).call

    assert_predicate report, :ok?, report.errors.inspect
    manifest = Mcweb::Plugins::Manifest.load_file(PLUGIN_ROOT.join("mcweb_plugin.yml"))
    permission = Mcweb::Plugins::PermissionContributionLoader.load(manifest).sole
    slot = Mcweb::Plugins::ContributionDocumentLoader.load(manifest)
      .find { |entry| entry.type == "ui_slot" }

    assert_equal "examples.forum_extension.moderation.review", permission.id
    assert_equal "/admin/forum/reports", slot.payload.fetch("target")
    assert_equal permission.id, slot.payload.fetch("permission")
  end
end
