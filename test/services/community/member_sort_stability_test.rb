# frozen_string_literal: true

require "test_helper"

module Community
  class MemberSortStabilityTest < ActiveSupport::TestCase
    test "every member directory sort has a deterministic id tie breaker" do
      tied_at = Time.current.change(usec: 0)
      first = create_user
      second = create_user
      User.where(id: [ first.id, second.id ]).update_all(
        created_at: tied_at,
        last_seen_at: tied_at
      )
      scope = User.where(id: [ first.id, second.id ])
      expected = [ first.id, second.id ].sort.reverse
      controller = MembersController.new
      controller.instance_variable_set(:@current_user, nil)

      %w[posts likes reviews purchases online active joined].each do |sort|
        actual = controller.send(:apply_member_sort, scope, sort).pluck(:id)

        assert_equal expected, actual, "#{sort} did not remain stable for tied members"
      end
    end

    test "purchase sort uses a correlated Arel count over completed orders" do
      controller_source = Rails.root.join(
        "app/controllers/community/members_controller.rb"
      ).read
      purchase_branch = controller_source[/when "purchases"(?<body>.*?)when "online"/m, :body]
      purchase_subquery = controller_source[
        /def member_purchase_count_subquery(?<body>.*?)def count_subquery/m,
        :body
      ]

      assert purchase_branch, "expected the purchases sort branch"
      assert purchase_subquery, "expected the purchase-count subquery"
      assert_includes purchase_branch,
                      "Arel::Nodes::Descending.new(member_purchase_count_subquery)"
      refute_includes purchase_branch, "Arel.sql"
      refute_includes purchase_branch, '#{'
      assert_includes purchase_subquery, "orders[:user_id].eq(users[:id])"
      assert_match(/where\(status:.*COMPLETED_ORDER_STATUSES/m, purchase_subquery)
      refute_includes purchase_subquery, "sanitize_sql"
      refute_includes purchase_subquery, "Arel.sql"

      tied_at = Time.current.change(usec: 0)
      buyer = create_user
      cancelled_only = create_user
      User.where(id: [ buyer.id, cancelled_only.id ]).update_all(created_at: tied_at)
      Commerce::Order.create!(
        user: buyer,
        status: "paid",
        subtotal_cents: 100,
        discount_cents: 0,
        total_cents: 100,
        currency: "CNY"
      )
      2.times do
        Commerce::Order.create!(
          user: cancelled_only,
          status: "cancelled",
          subtotal_cents: 100,
          discount_cents: 0,
          total_cents: 100,
          currency: "CNY"
        )
      end

      sorted_ids = MembersController.new.send(
        :apply_member_sort,
        User.where(id: [ buyer.id, cancelled_only.id ]),
        "purchases"
      ).pluck(:id)

      assert_equal [ buyer.id, cancelled_only.id ], sorted_ids
    end
  end
end
