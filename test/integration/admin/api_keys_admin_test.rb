# frozen_string_literal: true

require "test_helper"

module Admin
  class ApiKeysAdminTest < ActionDispatch::IntegrationTest
    setup do
      @admin = create_user
      grant_permission(@admin, "admin.access")
      grant_permission(@admin, "system.settings.manage")
      sign_in_as(@admin)
    end

    test "index renders" do
      get admin_system_api_keys_path
      assert_response :success
    end

    test "admin can create a key and the plaintext token is shown once" do
      assert_difference -> { Administration::ApiKey.count }, 1 do
        post admin_system_api_keys_path, params: { api_key: { name: "Integration", scopes: %w[read] } }
      end
      assert_redirected_to admin_system_api_keys_path
      assert_match(/mcw_/, flash[:notice], "created flash should contain the one-time token")

      key = Administration::ApiKey.order(:created_at).last
      assert_equal "Integration", key.name
      assert_equal %w[read], key.scope_list
    end

    test "creating a key bound to a user resolves the username" do
      @admin.update!(account_type: :owner)
      target = create_user(username: "apibounduser")
      post admin_system_api_keys_path, params: {
        api_key: { name: "Bound", scopes: %w[read write], username: "apibounduser" }
      }
      assert_redirected_to admin_system_api_keys_path
      key = Administration::ApiKey.order(:created_at).last
      assert_equal target.id, key.user_id
      assert key.allows?("write")
    end

    test "staff scopes require a bound user and preserve their fine-grained list" do
      assert_no_difference -> { Administration::ApiKey.count } do
        post admin_system_api_keys_path, params: {
          api_key: {
            name: "Unbound staff",
            scopes: %w[staff.moderation.read staff.moderation.note]
          }
        }
      end
      assert_redirected_to new_admin_system_api_key_path

      post admin_system_api_keys_path, params: {
        api_key: {
          name: "Bound staff",
          scopes: %w[staff.moderation.read staff.moderation.note],
          username: @admin.username
        }
      }
      assert_redirected_to admin_system_api_keys_path
      key = Administration::ApiKey.order(:created_at).last
      assert_equal @admin.id, key.user_id
      assert_equal %w[staff.moderation.read staff.moderation.note], key.scope_list
    end

    test "non-owner cannot bind a key to another user" do
      target = create_user(username: "apiotheruser")

      assert_no_difference -> { Administration::ApiKey.count } do
        post admin_system_api_keys_path, params: {
          api_key: { name: "Forbidden", scopes: %w[read], username: target.username }
        }
      end
      assert_redirected_to new_admin_system_api_key_path
    end

    test "unknown username is rejected" do
      assert_no_difference -> { Administration::ApiKey.count } do
        post admin_system_api_keys_path, params: { api_key: { name: "X", scopes: %w[read], username: "nope-nope" } }
      end
      assert_redirected_to new_admin_system_api_key_path
    end

    test "empty or unknown scopes are rejected" do
      assert_no_difference -> { Administration::ApiKey.count } do
        post admin_system_api_keys_path, params: { api_key: { name: "NoScope", scopes: [] } }
      end
      assert_redirected_to new_admin_system_api_key_path

      assert_no_difference -> { Administration::ApiKey.count } do
        post admin_system_api_keys_path, params: { api_key: { name: "UnknownScope", scopes: %w[admin] } }
      end
      assert_redirected_to new_admin_system_api_key_path
    end

    test "blank name is rejected" do
      assert_no_difference -> { Administration::ApiKey.count } do
        post admin_system_api_keys_path, params: { api_key: { name: "", scopes: %w[read] } }
      end
      assert_redirected_to new_admin_system_api_key_path
    end

    test "admin can revoke a key" do
      record, = Administration::ApiKey.generate!(name: "ToRevoke", scopes: %w[read])
      post revoke_admin_system_api_key_path(record)
      assert_redirected_to admin_system_api_keys_path
      assert record.reload.revoked?
    end

    test "admin access alone cannot manage api keys" do
      delete identity_session_path
      limited_admin = create_user(account_type: :admin)
      grant_permission(limited_admin, "admin.access")
      sign_in_as(limited_admin)

      get admin_system_api_keys_path
      assert_response :redirect

      assert_no_difference -> { Administration::ApiKey.count } do
        post admin_system_api_keys_path, params: { api_key: { name: "Forbidden", scopes: %w[read] } }
      end

      record, = Administration::ApiKey.generate!(name: "Protected", scopes: %w[read])
      post revoke_admin_system_api_key_path(record)
      assert_response :redirect
      assert_not record.reload.revoked?
    end

    test "non-admin cannot access api keys" do
      delete identity_session_path
      other = create_user
      sign_in_as(other)
      get admin_system_api_keys_path
      assert_response :redirect
      assert_not_equal 200, response.status
    end
  end
end
