# frozen_string_literal: true

require "test_helper"

class Mcweb::SidekiqWebFramePolicyTest < ActiveSupport::TestCase
  test "keeps the Sidekiq policy while restricting ancestors to the same origin" do
    body = [ "ok" ]
    app = lambda do |_environment|
      [
        200,
        {
          "content-security-policy" =>
            "default-src 'self'; script-src 'self'; frame-ancestors https://example.test",
          "x-frame-options" => "DENY"
        },
        body
      ]
    end

    status, headers, returned_body = Mcweb::SidekiqWebFramePolicy.new(app).call({})

    assert_equal 200, status
    assert_same body, returned_body
    assert_equal "SAMEORIGIN", headers.fetch("x-frame-options")
    assert_equal "default-src 'self'; script-src 'self'; frame-ancestors 'self'",
      headers.fetch("content-security-policy")
    assert headers.keys.none? { |key| key.match?(/[A-Z]/) }
  end

  test "adds an explicit policy when the mounted app returns none" do
    app = ->(_environment) { [ 302, { "Location" => "/jobs/" }, [] ] }

    _status, headers, _body = Mcweb::SidekiqWebFramePolicy.new(app).call({})

    assert_equal "frame-ancestors 'self'",
      headers.fetch("content-security-policy")
    assert_equal "SAMEORIGIN", headers.fetch("x-frame-options")
    assert_equal "/jobs/", headers.fetch("location")
  end

  test "marks only the actual successful Sidekiq HTML document" do
    body_class = Class.new do
      attr_reader :closed

      def each
        yield "<!doctype html><html><head><title>Sidekiq</title></head><body>ok</body></html>"
      end

      def close
        @closed = true
      end
    end
    body = body_class.new
    app = lambda do |_environment|
      [
        200,
        {
          "Content-Type" => "text/html; charset=utf-8",
          "Content-Length" => "1"
        },
        body
      ]
    end

    status, headers, returned_body = Mcweb::SidekiqWebFramePolicy.new(app).call({})
    document = returned_body.join

    assert_equal 200, status
    assert_includes document,
      '<meta name="mcweb-embedded-console" content="sidekiq">'
    assert_equal document.bytesize.to_s, headers.fetch("content-length")
    assert_predicate body, :closed
  end

  test "does not mark JSON redirects or failed HTML as a ready console" do
    responses = [
      [ 200, { "Content-Type" => "application/json" }, [ "{}" ] ],
      [ 302, { "Content-Type" => "text/html" }, [ "<html><head></head></html>" ] ],
      [ 500, { "Content-Type" => "text/html" }, [ "<html><head></head></html>" ] ]
    ]

    responses.each do |response|
      _status, _headers, body = Mcweb::SidekiqWebFramePolicy
        .new(->(_environment) { response })
        .call({})

      assert_not_includes body.join, "mcweb-embedded-console"
    end
  end

  test "the admin document only permits same-origin frame sources" do
    initializer = Rails.root.join(
      "config/initializers/content_security_policy.rb"
    ).read

    assert_includes initializer, "policy.frame_src :self"
    assert_not_includes initializer, "policy.frame_src :https"
  end
end
