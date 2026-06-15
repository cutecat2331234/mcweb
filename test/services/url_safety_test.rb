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

  test "http_https_url allows public http and https urls" do
    assert UrlSafety.http_https_url?("https://cdn.example.com/image.png")
    assert UrlSafety.http_https_url?("http://cdn.example.com/image.png")
  end

  test "http_https_url rejects javascript and other schemes" do
    assert_not UrlSafety.http_https_url?("javascript:alert(1)")
    assert_not UrlSafety.http_https_url?("data:text/html,<script>alert(1)</script>")
    assert_not UrlSafety.http_https_url?("//evil.com/image.png")
  end

  test "safe_image_src allows active storage paths and https urls" do
    assert UrlSafety.safe_image_src?("https://cdn.example.com/image.png")
    assert UrlSafety.safe_image_src?("/rails/active_storage/blobs/abc/image.png")
    assert_not UrlSafety.safe_image_src?("javascript:alert(1)")
  end
end

class Community::FetchLinkPreviewTest < ActiveSupport::TestCase
  test "rejects unsafe urls without fetching" do
    result = Community::FetchLinkPreview.call(url: "http://127.0.0.1/admin")
    assert result.failure?
    assert_equal "Invalid URL.", result.error
  end

  test "scrape_preview returns nil for unsafe urls" do
    service = Community::FetchLinkPreview.new(url: "http://127.0.0.1/secret")
    assert_nil service.send(:scrape_preview)
  end
end

class Community::FormatPostBodyOneboxSafetyTest < ActiveSupport::TestCase
  test "onebox omits unsafe preview image urls" do
    preview = {
      url: "https://example.com",
      title: "Example",
      description: "Desc",
      image_url: "javascript:alert(1)"
    }

    Rails.cache.write("forum/link_preview/#{Digest::SHA256.hexdigest('https://example.com')}", preview)

    result = Community::FormatPostBody.call(body: "https://example.com")
    assert result.success?
    assert_not_includes result.value, "javascript:"
    assert_not_includes result.value, "<img"
  end

  test "product onebox omits unsafe image urls" do
    product = Commerce::Product.create!(
      public_id: "prod_xss_test",
      name: "XSS Product",
      slug: "xss-product-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      price_cents: 100,
      currency: "CNY",
      status: "active",
      image_url: "https://cdn.example.com/safe.png"
    )
    product.update_column(:image_url, "javascript:alert(1)")

    result = Community::FormatPostBody.call(body: "/store/products/#{product.public_id}")
    assert result.success?
    assert_not_includes result.value, "javascript:"
    assert_not_includes result.value, "<img"
  end

  test "product model rejects unsafe image urls" do
    product = Commerce::Product.new(
      name: "Bad Image",
      slug: "bad-image-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      price_cents: 100,
      currency: "CNY",
      status: "active",
      image_url: "javascript:alert(1)"
    )

    assert_not product.valid?
    assert_includes product.errors[:image_url], "must be a safe http(s) or uploaded image URL"
  end
end
