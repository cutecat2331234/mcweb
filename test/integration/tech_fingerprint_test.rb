# frozen_string_literal: true

require "test_helper"

class TechFingerprintTest < ActionDispatch::IntegrationTest
  test "exposes rails fingerprint headers and meta tags by default" do
    get root_path
    assert_response :success

    assert_match %r{mod_rack/Ruby on Rails}, response.headers["X-Powered-By"].to_s
    assert_match(/Ruby on Rails/, response.body)
    assert_match(/name="generator"/, response.body)
    assert_match(/csrf-param/, response.body)
  end
end
