# frozen_string_literal: true

require "test_helper"

module Mcweb
  class FrontendApplicationTestHelperContractTest < ActiveSupport::TestCase
    class IntegrationHarness < ActionDispatch::IntegrationTest
      attr_reader :processed_request

      def process(method, path, **options)
        @processed_request = { method: method, path: path, options: options }
      end

      def identity_session_path
        "/app/identity/session"
      end
    end

    test "request_from preserves request options and owns application source headers" do
      harness = IntegrationHarness.new("request_from_contract")
      original_headers = {
        "Accept" => "application/json",
        "X-Request-ID" => "request-123",
        "X-McWeb-Application" => "forged-application",
        "Referer" => "https://forged.example/app"
      }

      harness.request_from(
        application_id: "staff",
        method: "patch",
        path: "/app/staff/example",
        referer: "http://www.example.com/app/staff",
        params: { value: "updated" },
        headers: original_headers,
        as: :json,
        xhr: true,
        env: { "test.contract" => "forwarded" }
      )

      request = harness.processed_request
      assert_equal :patch, request.fetch(:method)
      assert_equal "/app/staff/example", request.fetch(:path)
      assert_equal({ value: "updated" }, request.dig(:options, :params))
      assert_equal :json, request.dig(:options, :as)
      assert_equal true, request.dig(:options, :xhr)
      assert_equal "forwarded", request.dig(:options, :env, "test.contract")

      forwarded_headers = request.dig(:options, :headers)
      assert_equal "application/json", forwarded_headers.fetch("Accept")
      assert_equal "request-123", forwarded_headers.fetch("X-Request-ID")
      assert_equal "staff", forwarded_headers.fetch("X-McWeb-Application")
      assert_equal "http://www.example.com/app/staff", forwarded_headers.fetch("HTTP_REFERER")
      refute forwarded_headers.key?("Referer")
      assert_equal "forged-application", original_headers.fetch("X-McWeb-Application")
      assert_equal "https://forged.example/app", original_headers.fetch("Referer")
    end

    test "sign_out_from delegates a sourced DELETE without persisting headers" do
      harness = IntegrationHarness.new("sign_out_from_contract")

      harness.sign_out_from(
        application_id: "pvp",
        referer: "http://www.example.com/app/pvp",
        headers: { "Accept" => "text/html" },
        xhr: true
      )

      request = harness.processed_request
      assert_equal :delete, request.fetch(:method)
      assert_equal "/app/identity/session", request.fetch(:path)
      assert_nil request.dig(:options, :params)
      assert_equal true, request.dig(:options, :xhr)
      assert_equal "text/html", request.dig(:options, :headers, "Accept")
      assert_equal "pvp", request.dig(:options, :headers, "X-McWeb-Application")
      assert_equal "http://www.example.com/app/pvp", request.dig(:options, :headers, "HTTP_REFERER")
    end
  end
end
