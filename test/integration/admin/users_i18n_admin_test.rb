# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  class UsersI18nAdminTest < ActionDispatch::IntegrationTest
    test "English admin user list and detail contain localized functional labels" do
      owner = create_user(account_type: "owner", locale: "en")
      target = create_user(status: "active", locale: "en")
      sign_in_as(owner)

      get admin_users_path
      assert_response :success
      index_props = inertia.props.deep_symbolize_keys
      assert_equal "Users", index_props.fetch(:title)
      assert_equal %w[Username Email Status Joined],
                   index_props.fetch(:columns).map { |column| column.fetch(:label) }

      get admin_user_path(target)
      assert_response :success
      detail_props = inertia.props.deep_symbolize_keys
      fields = detail_props.fetch(:fields).index_by { |field| field.fetch(:label) }
      assert_equal "Active", fields.fetch("Status").fetch(:value)
      assert_equal "Yes", fields.fetch("Email verified").fetch(:value)
      localized_contract = {
        fields: detail_props.fetch(:fields),
        sections: detail_props.fetch(:sections),
        actions: detail_props.fetch(:actions),
        trust_levels: detail_props.dig(:trustLevelForm, :levels)
      }
      refute_match(/\p{Han}/, localized_contract.to_json)
    end

    test "Chinese admin user detail does not expose raw enum states" do
      owner = create_user(account_type: "owner", locale: "zh-CN")
      target = create_user(status: "banned", locale: "zh-CN")
      sign_in_as(owner)

      get admin_user_path(target)

      assert_response :success
      fields = inertia.props.deep_symbolize_keys.fetch(:fields).index_by { |field| field.fetch(:label) }
      assert_equal "已封禁", fields.fetch("状态").fetch(:value)
      refute_includes fields.values.map { |field| field.fetch(:value).to_s }, "banned"
    end
  end
end
