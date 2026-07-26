# frozen_string_literal: true

require "test_helper"
require Rails.root.join(
  "db/migrate/20260726125901_add_payment_reconciliation_run_permission"
)

class PaymentReconciliationRunPermissionMigrationTest < ActiveSupport::TestCase
  ROLE_KEYS = %w[owner super_admin].freeze

  test "upgrade grants the dedicated run permission to existing privileged roles" do
    roles = ROLE_KEYS.map do |key|
      Role.find_or_create_by!(key: key) do |role|
        role.name = key
        role.system_role = true
      end
    end

    Permission.find_by(
      key: AddPaymentReconciliationRunPermission::PERMISSION_KEY
    )&.destroy!

    AddPaymentReconciliationRunPermission.new.up

    permission = Permission.find_by!(
      key: AddPaymentReconciliationRunPermission::PERMISSION_KEY
    )
    assert_equal "store", permission.category
    assert_equal ROLE_KEYS.sort,
      permission.roles.where(id: roles.map(&:id)).pluck(:key).sort
  end
end
