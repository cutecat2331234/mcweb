# frozen_string_literal: true

require "test_helper"

class SafeRedirectTest < ActiveSupport::TestCase
  RedirectTester = Class.new do
    include SafeRedirect
    attr_reader :request

    def initialize(host:, referer: nil)
      @request = Struct.new(:host, :referer, keyword_init: true).new(host: host, referer: referer)
    end
  end

  test "allows same-site relative paths" do
    tester = RedirectTester.new(host: "example.com")

    assert_equal "/store/cart", tester.send(:safe_local_redirect_path, "/store/cart", fallback: "/")
    assert_equal "/forum?q=1", tester.send(:safe_local_redirect_path, "/forum?q=1", fallback: "/")
  end

  test "rejects protocol-relative and external paths" do
    tester = RedirectTester.new(host: "example.com")

    assert_equal "/fallback", tester.send(:safe_local_redirect_path, "//evil.com", fallback: "/fallback")
    assert_equal "/fallback", tester.send(:safe_local_redirect_path, "https://evil.com", fallback: "/fallback")
    assert_equal "/fallback", tester.send(:safe_local_redirect_path, "", fallback: "/fallback")
  end

  test "safe_referer_path only allows same host" do
    tester = RedirectTester.new(host: "example.com", referer: "https://example.com/store/cart")

    assert_equal "/store/cart", tester.send(:safe_referer_path, fallback: "/fallback")
  end

  test "safe_referer_path rejects foreign hosts" do
    tester = RedirectTester.new(host: "example.com", referer: "https://evil.com/phish")

    assert_equal "/fallback", tester.send(:safe_referer_path, fallback: "/fallback")
  end
end
