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
    assert_equal "SAMEORIGIN", headers.fetch("X-Frame-Options")
    assert_equal "default-src 'self'; script-src 'self'; frame-ancestors 'self'",
      headers.fetch("Content-Security-Policy")
    assert_not headers.key?("content-security-policy")
    assert_not headers.key?("x-frame-options")
  end

  test "adds an explicit policy when the mounted app returns none" do
    app = ->(_environment) { [ 302, { "Location" => "/jobs/" }, [] ] }

    _status, headers, _body = Mcweb::SidekiqWebFramePolicy.new(app).call({})

    assert_equal "frame-ancestors 'self'",
      headers.fetch("Content-Security-Policy")
    assert_equal "SAMEORIGIN", headers.fetch("X-Frame-Options")
    assert_equal "/jobs/", headers.fetch("Location")
  end

  test "the admin document only permits same-origin frame sources" do
    initializer = Rails.root.join(
      "config/initializers/content_security_policy.rb"
    ).read

    assert_includes initializer, "policy.frame_src :self"
    assert_not_includes initializer, "policy.frame_src :https"
  end
end
