# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Commerce
  class StoreCreditWalletTest < ActionDispatch::IntegrationTest
    include InertiaRails::Minitest

    setup do
      @user = create_user(store_credit_cents: 10_000)
      sign_in_as(@user)

      52.times do |index|
        Commerce::StoreCreditTransaction.create!(
          user: @user,
          amount_cents: 100,
          balance_before_cents: index * 100,
          balance_after_cents: (index + 1) * 100,
          note: "wallet-ledger-#{index}"
        )
      end
    end

    test "wallet exposes every transaction through a private stable cursor" do
      get store_wallet_path

      assert_response :success
      assert_equal "private, no-store", response.headers["Cache-Control"]
      assert_equal "Commerce/Wallet/Show", inertia.component
      first_props = inertia.props.deep_symbolize_keys
      first_rows = first_props.fetch(:transactions)
      assert_equal Commerce::StoreCreditLedgerPage::PAGE_SIZE, first_rows.length
      assert_equal first_rows.length, first_rows.pluck(:ledger_id).uniq.length
      assert first_rows.all? { |row| row.key?(:source_label) && row.key?(:balance_before_label) }
      assert_equal true, first_props.dig(:pagination, :has_more)

      get first_props.dig(:pagination, :next_url)

      assert_response :success
      second_props = inertia.props.deep_symbolize_keys
      second_rows = second_props.fetch(:transactions)
      assert_equal 2, second_rows.length
      assert_equal false, second_props.dig(:pagination, :has_more)
      assert_empty(first_rows.pluck(:ledger_id) & second_rows.pluck(:ledger_id))
    end

    test "invalid cursor returns to the safe ledger entry point" do
      get store_wallet_path, params: { cursor: "invalid" }

      assert_redirected_to store_wallet_path
      assert_equal I18n.t("mcweb.services.errors.store_credit_cursor_invalid"), flash[:alert]
    end
  end
end
