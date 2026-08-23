# frozen_string_literal: true

require "test_helper"

class FrontendApplicationBoundaryTest < ActionDispatch::IntegrationTest
  test "cross-application Inertia GET becomes a no-store document recovery" do
    get "/app/forum/latest", headers: {
      "X-Inertia" => "true",
      "X-Inertia-Version" => "boundary-test",
      "X-McWeb-Application" => "store"
    }

    assert_response :conflict
    assert_equal "/app/forum/latest", response.headers["X-Inertia-Location"]
    assert_includes response.headers.fetch("Cache-Control"), "no-store"
    vary = response.headers.fetch("Vary").split(",").map(&:strip)
    assert_includes vary, "X-Inertia"
    assert_includes vary, "X-McWeb-Application"
  end

  test "cross-application mutation is rejected without replay location" do
    post "/app/forum/drafts", params: { draft: {} }, headers: {
      "X-Inertia" => "true",
      "X-McWeb-Application" => "account"
    }

    assert_response :conflict
    assert_nil response.headers["X-Inertia-Location"]
    assert_equal "/app/forum/latest", response.headers["X-McWeb-Safe-Location"]
  end

  test "download endpoint cannot be absorbed by an application visit" do
    get "/app/store/orders/example/receipt_pdf", headers: {
      "X-Inertia" => "true",
      "X-McWeb-Application" => "store"
    }

    assert_response :conflict
    assert_equal "/app/store/orders/example/receipt_pdf",
      response.headers["X-Inertia-Location"]
  end

  test "unknown shared-action source is rejected before controller callbacks" do
    patch "/locale", params: { locale: "en" }, headers: {
      "X-McWeb-Application" => "forged-application",
      "Accept" => "application/json"
    }

    assert_response :conflict
    assert_nil response.headers["X-Inertia-Location"]
  end
end
