# frozen_string_literal: true

require "test_helper"

class BadgeGroupingTest < ActiveSupport::TestCase
  test "defaults to general and is settable" do
    badge = Community::Badge.create!(name: "Helper", slug: "h-#{SecureRandom.hex(3)}", grant_rule: "manual")
    assert_equal "general", badge.grouping

    badge.update!(grouping: "Community")
    assert_equal "Community", badge.reload.grouping
  end
end
