# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  class StoreCreditUsersAdminTest < ActionDispatch::IntegrationTest
    setup do
      @actor = create_user(
        account_type: "staff",
        username: "credit_staff_#{SecureRandom.hex(3)}"
      )
      @target = create_user(
        username: "credit_member_#{SecureRandom.hex(3)}",
        display_name: "Visible Balance Member",
        email: "private-credit-#{SecureRandom.hex(4)}@example.com",
        store_credit_cents: 12_345,
        status: "banned",
        ban_reason: "PRIVATE_CREDIT_BAN_REASON"
      )
      @sensitive_role = Role.create!(
        name: "PRIVATE CREDIT ROLE",
        key: "private_credit_role_#{SecureRandom.hex(4)}"
      )
      @target.roles << @sensitive_role
      Community::UserWarning.create!(
        user: @target,
        issuer: @actor,
        reason: "PRIVATE CREDIT WARNING",
        points: 2
      )
      Community::StaffNote.create!(
        user: @target,
        author: @actor,
        body: "PRIVATE CREDIT STAFF NOTE"
      )

      grant_permission(@actor, "admin.access")
      grant_permission(@actor, "store.credit.read")
      grant_permission(@actor, "store.credit.adjust")
      grant_admin_module(@actor, "store")
      sign_in_as(@actor)
    end

    test "store-only staff can reach the credit directory from bounded navigation props" do
      get admin_root_path

      assert_response :success
      user_props = inertia.props.deep_symbolize_keys.dig(:auth, :user)
      assert_equal [ "store" ], user_props.fetch(:admin_modules)
      assert_includes user_props.fetch(:admin_permissions), "store.credit.adjust"
      assert_includes user_props.fetch(:admin_permissions), "store.credit.read"
      assert_not_includes user_props.fetch(:admin_permissions), "system.settings.manage"

      get admin_store_credit_users_path

      assert_response :success
      assert_equal "Admin/Generic/Index", inertia.component
      props = inertia.props.deep_symbolize_keys
      assert_equal I18n.t("mcweb.admin.store_credit_users.title"), props.fetch(:title)
      assert_equal(
        %w[username store_credit],
        props.fetch(:columns).map { |column| column.fetch(:key) }
      )
      row = props.fetch(:rows).find { |candidate| candidate[:username] == @target.username }
      assert row
      assert_equal(
        %i[store_credit url username],
        row.keys.sort
      )
      assert_equal admin_store_credit_user_path(@target), row.fetch(:url)
      assert_equal admin_store_credit_users_path, props.dig(:search, :action)
      assert_equal "", props.dig(:search, :query)
      assert_sensitive_target_values_absent(props)
    end

    test "credit directory search uses only public names and never email" do
      get admin_store_credit_users_path, params: { q: @target.email }

      assert_response :success
      refute_includes inertia.props.deep_symbolize_keys.fetch(:rows).pluck(:username), @target.username

      get admin_store_credit_users_path, params: { q: "Visible Balance" }

      assert_response :success
      assert_includes inertia.props.deep_symbolize_keys.fetch(:rows).pluck(:username), @target.username
    end

    test "credit detail is an explicit safe projection with the existing adjustment form" do
      get admin_store_credit_user_path(@target)

      assert_response :success
      assert_equal "Admin/Generic/Show", inertia.component
      props = inertia.props.deep_symbolize_keys
      assert_equal @target.username, props.fetch(:title)
      assert_equal [], props.fetch(:sections)
      assert_equal admin_store_credit_users_path, props.fetch(:backUrl)
      assert_equal(
        [ [ nil, @target.username ], [ "store_credit", "¥123.45" ] ],
        props.fetch(:fields).map { |field| [ field[:key], field.fetch(:value) ] }
      )

      store_credit_form = props.fetch(:storeCreditForm)
      assert_equal(
        authorize_store_credit_adjustment_admin_user_path(@target),
        store_credit_form.fetch(:authorization_url)
      )
      assert_equal(
        adjust_store_credit_admin_user_path(@target),
        store_credit_form.fetch(:action_url)
      )
      assert_equal 12_345, store_credit_form.fetch(:balance_cents)

      %i[
        accountForm
        actions
        badgeForm
        banForm
        muteForm
        silenceForm
        spamCleanForm
        staffNoteForm
        trustLevelForm
        warningForm
      ].each do |sensitive_prop|
        refute props.key?(sensitive_prop), "#{sensitive_prop} must not be exposed"
      end
      assert_sensitive_target_values_absent(props)
    end

    test "credit directory hides self and protected owner targets" do
      owner = create_user(
        account_type: "owner",
        username: "credit_owner_#{SecureRandom.hex(3)}",
        store_credit_cents: 9_999
      )

      get admin_store_credit_users_path

      usernames = inertia.props.deep_symbolize_keys.fetch(:rows).pluck(:username)
      refute_includes usernames, @actor.username
      refute_includes usernames, owner.username

      get admin_store_credit_user_path(@actor)
      assert_response :not_found

      get admin_store_credit_user_path(owner)
      assert_response :not_found
    end

    test "store-only staff cannot fall through to the full system user pages" do
      get admin_users_path
      assert_redirected_to admin_root_path

      get admin_user_path(@target)
      assert_redirected_to admin_root_path
    end

    test "credit directory requires both the store module and dedicated permission" do
      without_permission = create_user(account_type: "staff")
      grant_permission(without_permission, "admin.access")
      grant_admin_module(without_permission, "store")
      reset!
      sign_in_as(without_permission)

      get admin_store_credit_users_path
      assert_redirected_to root_path

      without_module = create_user(account_type: "staff")
      grant_permission(without_module, "admin.access")
      grant_permission(without_module, "store.credit.read")
      grant_admin_module(without_module, "forum")
      reset!
      sign_in_as(without_module)

      get admin_store_credit_users_path
      assert_redirected_to admin_root_path
    end

    test "balance read and adjustment permissions are independent" do
      read_only = create_user(account_type: "staff")
      grant_permission(read_only, "admin.access")
      grant_permission(read_only, "store.credit.read")
      grant_admin_module(read_only, "store")
      reset!
      sign_in_as(read_only)

      get admin_store_credit_user_path(@target)
      assert_response :success
      assert_nil inertia.props.deep_symbolize_keys.fetch(:storeCreditForm)

      adjust_only = create_user(account_type: "staff")
      grant_permission(adjust_only, "admin.access")
      grant_permission(adjust_only, "store.credit.adjust")
      grant_admin_module(adjust_only, "store")
      reset!
      sign_in_as(adjust_only)

      get admin_store_credit_users_path
      assert_redirected_to root_path

      post authorize_store_credit_adjustment_admin_user_path(@target),
        params: {
          amount_cents: 100,
          note: "Permission boundary check",
          request_id: SecureRandom.uuid
        },
        as: :json
      assert_response :success
    end

    test "system user detail does not disclose balance without the store read permission" do
      system_only = create_user(account_type: "staff")
      grant_permission(system_only, "admin.access")
      grant_permission(system_only, "system.settings.manage")
      grant_admin_module(system_only, "system")
      reset!
      sign_in_as(system_only)

      get admin_user_path(@target)

      assert_response :success
      props = inertia.props.deep_symbolize_keys
      refute_includes props.fetch(:fields).filter_map { |field| field[:key] }, "store_credit"
      assert_nil props.fetch(:storeCreditForm)
    end

    test "system user management keeps its original full projection" do
      grant_permission(@actor, "system.settings.manage")
      grant_admin_module(@actor, "system")

      get admin_users_path

      assert_response :success
      props = inertia.props.deep_symbolize_keys
      assert_includes props.fetch(:columns).map { |column| column.fetch(:key) }, "email"
      assert_includes props.fetch(:rows).pluck(:email), @target.email

      get admin_user_path(@target)

      assert_response :success
      props = inertia.props.deep_symbolize_keys
      assert_equal @target.email, props.fetch(:subtitle)
      assert props.fetch(:banForm)
      assert props.fetch(:warningForm).nil?
    end

    private

    def assert_sensitive_target_values_absent(props)
      serialized = JSON.generate(props)
      [
        @target.email,
        @target.ban_reason,
        @sensitive_role.name,
        "PRIVATE CREDIT WARNING",
        "PRIVATE CREDIT STAFF NOTE"
      ].each do |sensitive_value|
        refute_includes serialized, sensitive_value
      end
    end
  end
end
