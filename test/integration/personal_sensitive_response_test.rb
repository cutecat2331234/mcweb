# frozen_string_literal: true

require "test_helper"

class PersonalSensitiveResponseTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    enable_store_feature!(:shipping)
    sign_in_as(@user)
  end

  test "personal identity and commerce pages are private and never stored" do
    paths = [
      account_path,
      identity_sessions_management_index_path,
      store_shipping_addresses_path,
      store_orders_path,
      store_wallet_path
    ]

    paths.each do |path|
      get path

      assert_response :success, "expected #{path} to load"
      assert_equal "private, no-store", response.headers["Cache-Control"], path
    end
  end
end
