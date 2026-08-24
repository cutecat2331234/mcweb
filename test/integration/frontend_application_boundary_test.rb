# frozen_string_literal: true

require "test_helper"

class FrontendApplicationBoundaryTest < ActionDispatch::IntegrationTest
  test "integration authentication identifies the account application source" do
    user = create_user

    sign_in_as(user)

    assert session[Authentication::SESSION_COOKIE].present? ||
      cookies[Authentication::SESSION_COOKIE].present?
  end

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
      "X-McWeb-Application" => "account",
      "HTTP_REFERER" => "http://www.example.com/app/account"
    }

    assert_response :conflict
    assert_nil response.headers["X-Inertia-Location"]
    assert_equal "/app/forum/latest", response.headers["X-McWeb-Safe-Location"]
    assert_equal "account", request.headers["X-McWeb-Application"]
    assert_equal "http://www.example.com/app/account", request.referer
  end

  test "raw non-Inertia mutation without a source remains a document recovery" do
    post "/app/forum/drafts",
      params: { draft: {} },
      frontend_application_source: false

    assert_response :see_other
    assert_redirected_to "/app/forum/latest"
    assert_nil request.headers["X-McWeb-Application"]
    assert_nil request.referer
  end

  test "raw Inertia mutation without a source remains a conflict" do
    post "/app/forum/drafts",
      params: { draft: {} },
      headers: { "X-Inertia" => "true" },
      frontend_application_source: false

    assert_response :conflict
    assert_nil response.headers["X-Inertia-Location"]
    assert_equal "/app/forum/latest", response.headers["X-McWeb-Safe-Location"]
    assert_nil request.headers["X-McWeb-Application"]
    assert_nil request.referer
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
    assert_equal "forged-application", request.headers["X-McWeb-Application"]
    assert_nil request.referer
  end
end
