# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  class UserAccountAccessAdminTest < ActionDispatch::IntegrationTest
    setup do
      @owner = create_user(account_type: "owner")
      @staff = create_user(account_type: "staff")
      @role = Role.create!(
        key: "identity_support_#{SecureRandom.hex(4)}",
        name: "Identity support",
        description: "Identity support role"
      )
      sign_in_as(@owner)
    end

    test "owner account form exposes and persists the identity module grant" do
      get admin_user_path(@staff)

      assert_response :success
      account_form = inertia.props.deep_symbolize_keys.fetch(:accountForm)
      assert_includes account_form.fetch(:module_options), "identity"

      patch admin_user_path(@staff), params: {
        user: {
          display_name: @staff.display_name,
          locale: @staff.locale,
          time_zone: @staff.time_zone,
          account_type: "staff",
          admin_modules: [ "identity" ],
          role_ids: [ @role.id ]
        }
      }

      assert_redirected_to admin_user_path(@staff)
      assert @staff.reload.admin_module_grants.exists?(module_key: "identity")
      assert_equal [ @role.id ], @staff.role_ids
    end
  end
end
