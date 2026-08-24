# frozen_string_literal: true

require "test_helper"

class CiExitStatusFailureTest < ActiveSupport::TestCase
  test "the Rails test process reports an intentional failure" do
    canary_path = ENV.fetch("MCWEB_CI_FAILURE_CANARY_PATH")
    File.write(canary_path, "executed")

    flunk "intentional CI exit-status canary"
  end
end
