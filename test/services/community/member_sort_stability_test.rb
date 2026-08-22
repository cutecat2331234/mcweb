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
  end
end
