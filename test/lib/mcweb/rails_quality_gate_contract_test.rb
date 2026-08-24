# frozen_string_literal: true

require "test_helper"

module Mcweb
  class RailsQualityGateContractTest < ActiveSupport::TestCase
    test "the CI Rails gate proves failures return a nonzero process status" do
      gate = Rails.root.join("scripts/run-rails-quality-gate.sh").read
      canary = Rails.root.join("test/fixtures/ci_exit_status_failure_test.rb").read
      helper = Rails.root.join("test/test_helper.rb").read

      assert_includes gate, "MCWEB_CI_FAILURE_CANARY_PATH"
      assert_includes gate, "test/fixtures/ci_exit_status_failure_test.rb"
      assert_includes gate, "Rails test runner returned success for an intentional failure"
      assert_includes gate, 'bin/rails test "$@"'
      assert_includes canary, 'File.write(canary_path, "executed")'
      assert_includes canary, 'flunk "intentional CI exit-status canary"'
      assert_includes helper, 'require "minitest/reporters" unless ENV["CI"].present?'
    end
  end
end
