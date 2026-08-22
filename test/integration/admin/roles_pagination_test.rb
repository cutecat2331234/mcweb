# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  class RolesPaginationTest < ActionDispatch::IntegrationTest
    setup do
      admin = create_user(account_type: "owner")
      grant_permission(admin, "admin.access")
      grant_permission(admin, "system.settings.manage")
      grant_admin_module(admin, "system")
      sign_in_as(admin)

      30.times do |index|
        Role.create!(
          name: "Pagination role #{index}",
          key: "pagination_role_#{SecureRandom.hex(4)}_#{index}"
        )
      end
    end

    test "role index exposes paginated role cards and metadata" do
      get admin_roles_path

      assert_response :success
      assert_equal "Admin/Roles/Index", inertia.component
      props = inertia.props.deep_symbolize_keys
      assert_equal 25, props[:roles].size
      assert_equal 1, props.dig(:pagination, :page)
      assert_operator props.dig(:pagination, :pages), :>=, 2
      assert_equal Role.count, props.dig(:pagination, :count)

      get admin_roles_path(page: 2)

      assert_response :success
      page_two = inertia.props.deep_symbolize_keys
      assert_equal 2, page_two.dig(:pagination, :page)
      assert page_two[:roles].any?
    end

    test "an out-of-range page redirects to the canonical last page and preserves query parameters" do
      expected_last_page = (Role.count.to_f / 25).ceil

      get admin_roles_path(page: expected_last_page + 10, probe: "preserved")

      assert_response :found
      location = URI.parse(response.location)
      query = Rack::Utils.parse_nested_query(location.query)
      assert_equal admin_roles_path, location.path
      assert_equal expected_last_page.to_s, query.fetch("page")
      assert_equal "preserved", query.fetch("probe")

      follow_redirect!

      assert_response :success
      assert_equal expected_last_page, inertia.props.deep_symbolize_keys.dig(:pagination, :page)
    end
  end
end
