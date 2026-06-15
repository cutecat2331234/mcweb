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

class StoreReturnLocationTest < ActiveSupport::TestCase
  Controller = Class.new do
    include SafeRedirect

    attr_reader :request, :session

    def initialize(fullpath)
      @request = Struct.new(:fullpath, :get?, :xhr?).new(fullpath, true, false)
      @session = {}
    end

    def store_return_location
      return unless request.get? && !request.xhr?

      path = safe_local_redirect_path(request.fullpath, fallback: nil)
      session[:return_to] = path if path.present?
    end
  end

  test "does not store protocol-relative paths" do
    controller = Controller.new("//evil.com")

    controller.store_return_location

    assert_nil controller.session[:return_to]
  end

  test "stores safe relative paths" do
    controller = Controller.new("/forum/topics/abc")

    controller.store_return_location

    assert_equal "/forum/topics/abc", controller.session[:return_to]
  end
end
