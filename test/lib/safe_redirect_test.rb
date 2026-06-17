# frozen_string_literal: true

require "test_helper"

class SafeRedirectTest < ActiveSupport::TestCase
  class Harness
    include SafeRedirect
  end

  setup do
    @harness = Harness.new
  end

  test "safe_local_redirect_path normalizes legacy forum paths" do
    path = @harness.send(:safe_local_redirect_path, "/forum/topics/abc", fallback: "/fallback")
    assert_equal "/app/forum/topics/abc", path
  end

  test "safe_local_redirect_path rejects protocol-relative urls" do
    assert_equal "/fallback", @harness.send(:safe_local_redirect_path, "//evil.com", fallback: "/fallback")
  end
end

class SafeLocalPathTest < ActiveSupport::TestCase
  test "safe_local_path normalizes legacy store paths" do
    controller = ApplicationController.new
    assert_equal "/app/store/orders/ord1", controller.safe_local_path("/store/orders/ord1")
  end

  test "safe_local_path rejects protocol-relative paths" do
    controller = ApplicationController.new
    assert_nil controller.safe_local_path("//evil.com")
  end

  test "safe_local_path rejects paths with backslashes" do
    controller = ApplicationController.new
    assert_nil controller.safe_local_path("/store\\evil")
  end
end
