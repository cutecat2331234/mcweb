# frozen_string_literal: true

require "test_helper"
require "mcweb/test_log_path"

class Mcweb::TestLogPathTest < ActiveSupport::TestCase
  test "single-worker tests retain the conventional test log" do
    path = Mcweb::TestLogPath.resolve(root: Rails.root, environment: {})

    assert_equal Rails.root.join("log/test.log"), path
  end

  test "parallel workers receive isolated log paths" do
    path = Mcweb::TestLogPath.resolve(
      root: Rails.root,
      environment: { "TEST_ENV_NUMBER" => "3" }
    )

    assert_equal Rails.root.join("log/test3.log"), path
  end

  test "an explicit relative log path is resolved from the application root" do
    path = Mcweb::TestLogPath.resolve(
      root: Rails.root,
      environment: { "MCWEB_TEST_LOG_PATH" => "tmp/acceptance.log" }
    )

    assert_equal Rails.root.join("tmp/acceptance.log"), path
  end
end
