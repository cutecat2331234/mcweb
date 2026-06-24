# frozen_string_literal: true

require "test_helper"

class BadgeTierTest < ActiveSupport::TestCase
  test "defaults to bronze" do
    badge = Community::Badge.create!(name: "Helper", slug: "h-#{SecureRandom.hex(3)}", grant_rule: "manual")
    assert_equal "bronze", badge.tier
  end

  test "accepts valid tiers and rejects unknown ones" do
    badge = Community::Badge.new(name: "Helper", slug: "h-#{SecureRandom.hex(3)}", grant_rule: "manual")
    badge.tier = "gold"
    assert badge.valid?
    badge.tier = "platinum"
    assert_not badge.valid?
  end
end
