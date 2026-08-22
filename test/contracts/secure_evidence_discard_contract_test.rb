# frozen_string_literal: true

require "test_helper"

module SecureEvidence
  class DiscardContractTest < ActiveSupport::TestCase
    test "discard keeps upload before attachment lock order and schedules after commit" do
      source = Rails.root.join(
        "app/services/secure_evidence/discard_attachment.rb"
      ).read

      upload_lock = source.index("upload.lock!")
      attachment_lock = source.index("Attachment.lock.find_by")
      assert upload_lock
      assert attachment_lock
      assert_operator upload_lock, :<, attachment_lock
      assert_includes source, "ActiveRecord.after_all_transactions_commit"
      refute_match(/attachment\.(?:destroy|delete)/, source)
    end

    test "scan claim and result paths both fail closed after cleanup starts" do
      scan_source = Rails.root.join(
        "app/services/community/scan_post_attachment.rb"
      ).read
      sync_source = Rails.root.join(
        "app/services/secure_evidence/sync_scan_result.rb"
      ).read

      assert_operator scan_source.scan("cleanup_started?").length, :>=, 3
      assert_includes sync_source, "attachment.state_purge_pending?"
      assert_includes sync_source, "attachment.state_purged?"
    end

    test "quota and public API use active states and an explicit destroy contract" do
      creation_source = Rails.root.join(
        "app/services/secure_evidence/create_attachment.rb"
      ).read
      routes_source = Rails.root.join("config/routes.rb").read

      assert_includes creation_source, "state: Attachment::ACTIVE_STATES"
      assert_includes routes_source, "only: %i[create show destroy]"
    end
  end
end
