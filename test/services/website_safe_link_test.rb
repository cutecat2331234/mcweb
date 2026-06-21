# frozen_string_literal: true

require "test_helper"

class Website::SafeLinkTest < ActiveSupport::TestCase
  test "allows relative and https urls" do
    assert_equal "/blog", Website::SafeLink.sanitize_href("/blog")
    assert_equal "https://example.com", Website::SafeLink.sanitize_href("https://example.com")
  end

  test "rejects javascript and protocol-relative urls" do
    assert_nil Website::SafeLink.sanitize_href("javascript:alert(1)")
    assert_nil Website::SafeLink.sanitize_href("//evil.example")
  end
end
