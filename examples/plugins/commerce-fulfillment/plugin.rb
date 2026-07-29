# frozen_string_literal: true

Mcweb::Plugins.register do |plugin|
  plugin.fulfillment_provider("direct") do |request|
    # delivery_id is stable across retries and must be used as the provider's
    # idempotency key. No customer identity, address or payment metadata crosses
    # this boundary.
    {
      status: "succeeded",
      external_reference: "reference:#{request.fetch('delivery_id')}"
    }
  end

  plugin.on("commerce.order.paid") do |event|
    order = event.data["order"] || {}
    order_public_id = order["public_id"] || event.data["order_public_id"]
    next if order_public_id.blank?

    # commerce.order.paid is emitted only after the core payment transaction
    # commits. The stable key makes repeated delivery enqueue exactly one run.
    plugin.api.jobs.enqueue(
      job_key: "fulfill",
      arguments: {
        "order_public_id" => order_public_id,
        "fail_until_attempt" => 0
      },
      idempotency_key: "fulfillment:#{order_public_id}:v1"
    )
  end

  plugin.job("fulfill") do |arguments, context|
    fail_until_attempt = arguments.fetch("fail_until_attempt", 0)
    if context.attempt <= fail_until_attempt
      raise "reference provider temporary failure"
    end

    plugin.api.events.publish(
      "examples.commerce_fulfillment.completed",
      "order_public_id" => arguments.fetch("order_public_id"),
      "job_public_id" => context.run_public_id,
      "attempt" => context.attempt
    )
  end
end
