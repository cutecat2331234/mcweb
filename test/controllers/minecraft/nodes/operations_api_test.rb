# frozen_string_literal: true

require "test_helper"

class Minecraft::Nodes::OperationsApiTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    clear_enqueued_jobs
    @node = Minecraft::Node.create!(
      name: "Protocol Node",
      status: :online,
      metadata: {
        "node_protocol_versions" => [ 1, 2 ],
        "operation_types" => %w[collect_metrics sync_files]
      }
    )
    @secret = @node.generate_node_secret!
    @timestamp = Time.current.to_i
    @server = Minecraft::Server.create!(
      name: "Protocol Server",
      public_id: "srv_protocol_#{SecureRandom.hex(4)}",
      node: @node,
      process_driver: "script",
      process_config: { "status" => "true" },
      working_directory: "/srv/protocol",
      status: :online
    )
    result = Minecraft::EnqueueNodeOperation.call(
      operation_type: "collect_metrics",
      servers: [ @server ],
      idempotency_key: "protocol-operation"
    )
    @operation = result.value.fetch(:operation)
    Minecraft::PrepareNodeOperationJob.perform_now
  end

  teardown do
    clear_enqueued_jobs
  end

  test "v2 API dispatches one string-identified batch and requires explicit acknowledgement" do
    get node_path("operations/next"), headers: signed_headers("")

    assert_response :success
    batch = response.parsed_body.fetch("batch")
    assert_kind_of String, batch.fetch("id")
    assert_equal @operation.public_id, batch.fetch("operation_id")
    assert_equal [ @server.public_id ], batch.fetch("targets").pluck("target_key")

    completion_body = {
      delivery_id: batch.fetch("delivery_id"),
      payload_digest: batch.fetch("payload_digest"),
      target_results: [
        {
          target_key: @server.public_id,
          status: "completed",
          result: { success: true, status: "completed" },
          completed_at: Time.current.iso8601
        }
      ]
    }.to_json
    post node_path("operations/#{batch.fetch('id')}/complete"),
      params: completion_body,
      headers: signed_headers(completion_body)

    assert_response :success
    acknowledgement_id = response.parsed_body.fetch("acknowledgement_id")
    assert_not response.parsed_body.fetch("acknowledged")

    get node_path("operations/next"), headers: signed_headers("")
    assert_response :success
    assert_nil response.parsed_body.fetch("batch")

    acknowledgement_body = {
      delivery_id: batch.fetch("delivery_id"),
      payload_digest: batch.fetch("payload_digest"),
      acknowledgement_id: acknowledgement_id
    }.to_json
    post node_path("operations/#{batch.fetch('id')}/acknowledge"),
      params: acknowledgement_body,
      headers: signed_headers(acknowledgement_body)

    assert_response :success
    assert response.parsed_body.fetch("acknowledged")
    assert_equal "completed", response.parsed_body.fetch("status")
  end

  test "legacy task ids are serialized as strings" do
    task = Minecraft::NodeTask.create!(
      node: @node,
      server: @server,
      task_type: "collect_metrics",
      delivery_id: SecureRandom.uuid,
      status: "pending"
    )

    get node_path("tasks"), headers: signed_headers("")

    assert_response :success
    assert_equal task.id.to_s, response.parsed_body.fetch("tasks").sole.fetch("id")
  end

  private

  def node_path(suffix)
    "/minecraft/nodes/#{@node.public_id}/#{suffix}"
  end

  def signed_headers(body)
    @timestamp += 1
    timestamp = @timestamp.to_s
    signature = OpenSSL::HMAC.hexdigest("SHA256", @secret, "#{timestamp}.#{body}")
    {
      "CONTENT_TYPE" => "application/json",
      "X-Node-Timestamp" => timestamp,
      "X-Node-Signature" => signature
    }
  end
end
