# frozen_string_literal: true

require "test_helper"

class Mcweb::PathsTest < ActiveSupport::TestCase
  test "normalize leaves app paths unchanged" do
    assert_equal "/app/forum/topics/abc", Mcweb::Paths.normalize("/app/forum/topics/abc")
  end

  test "normalize upgrades legacy forum paths" do
    assert_equal "/app/forum/topics/abc", Mcweb::Paths.normalize("/forum/topics/abc")
  end

  test "normalize upgrades legacy store paths with query and hash" do
    assert_equal "/app/store/orders/ord1", Mcweb::Paths.normalize("/store/orders/ord1")
    assert_equal "/app/store/products/p1#reviews", Mcweb::Paths.normalize("/store/products/p1#reviews")
  end

  test "normalize leaves website paths unchanged" do
    assert_equal "/blog/hello", Mcweb::Paths.normalize("/blog/hello")
  end

  test "normalize leaves absolute urls unchanged" do
    assert_equal "https://example.com/forum/x", Mcweb::Paths.normalize("https://example.com/forum/x")
  end
end
