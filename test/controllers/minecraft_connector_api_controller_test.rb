# frozen_string_literal: true

require "test_helper"

class MinecraftConnectorApiControllerTest < ActionController::TestCase
  tests Minecraft::Connector::ApiController

  test "task result params defaults to an empty hash when result is omitted" do
    @controller.params = ActionController::Parameters.new({})

    assert_equal({}, @controller.send(:task_result_params))
  end
end
