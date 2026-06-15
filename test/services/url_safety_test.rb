# frozen_string_literal: true

require "test_helper"

class UrlSafetyTest < ActiveSupport::TestCase
  test "allows public https urls" do
    assert UrlSafety.public_http_url?("https://example.com/page")
  end

  test "blocks localhost" do
    assert_not UrlSafety.public_http_url?("http://localhost/admin")
    assert_not UrlSafety.public_http_url?("http://127.0.0.1/secret")
  end

  test "blocks private ip literals" do
    assert_not UrlSafety.public_http_url?("http://192.168.0.1/status")
    assert_not UrlSafety.public_http_url?("http://10.0.0.5/")
  end

  test "blocks metadata host" do
    assert_not UrlSafety.public_http_url?("http://metadata.google.internal/computeMetadata/v1/")
  end

  test "blocks urls with embedded credentials" do
    assert_not UrlSafety.public_http_url?("http://user:pass@127.0.0.1/admin")
  end

  test "blocks cgnat addresses" do
    assert_not UrlSafety.public_http_url?("http://100.64.0.1/status")
  end
end

class Community::FetchLinkPreviewTest < ActiveSupport::TestCase
  test "rejects unsafe urls without fetching" do
    result = Community::FetchLinkPreview.call(url: "http://127.0.0.1/admin")
    assert result.failure?
    assert_equal "Invalid URL.", result.error
  end
end
