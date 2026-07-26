# frozen_string_literal: true

require "test_helper"
require Rails.root.join(
  "db/migrate/20260726125900_add_forum_attachment_security_manage_permission"
)

class AttachmentSecurityPermissionMigrationTest < ActiveSupport::TestCase
  ROLE_KEYS = %w[owner super_admin forum_admin].freeze

  test "upgrade provisions the attachment security permission for existing privileged roles" do
    roles = ROLE_KEYS.map do |key|
      Role.find_or_create_by!(key: key) do |role|
        role.name = key
        role.system_role = true
      end
    end

    Permission.find_by(
      key: AddForumAttachmentSecurityManagePermission::PERMISSION_KEY
    )&.destroy!

    AddForumAttachmentSecurityManagePermission.new.up

    permission = Permission.find_by!(
      key: AddForumAttachmentSecurityManagePermission::PERMISSION_KEY
    )
    assert_equal "forum", permission.category
    assert_equal ROLE_KEYS.sort,
      permission.roles.where(id: roles.map(&:id)).pluck(:key).sort
  end
end
