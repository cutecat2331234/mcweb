# frozen_string_literal: true

require "test_helper"

class Commerce::StoreFeaturesTest < ActiveSupport::TestCase
  test "physical shipping and gift wrap default to disabled" do
    Commerce::StoreFeatures.definitions.each do |definition|
      SiteSetting.where(key: definition.key).delete_all
    end

    assert_not Commerce::StoreFeatures.enabled?(:physical_products)
    assert_not Commerce::StoreFeatures.enabled?(:shipping)
    assert_not Commerce::StoreFeatures.enabled?(:gift_wrap)
    assert_not Commerce::StoreFeatures.enabled?(:order_shipping_management)
    assert_equal(
      { "physical_products" => false, "shipping" => false, "gift_wrap" => false, "order_shipping_management" => false },
      Commerce::StoreFeatures.frontend_hash
    )
  end

  test "update_from_params toggles site settings" do
    Commerce::StoreFeatures.update_from_params!({ "shipping" => "1", "gift_wrap" => "0" })

    assert Commerce::StoreFeatures.enabled?(:shipping)
    assert_not Commerce::StoreFeatures.enabled?(:gift_wrap)
  end
end

class Commerce::BuildConnectorTaskPayloadTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @order = Commerce::Order.create!(
      public_id: "ord_#{SecureRandom.alphanumeric(16)}",
      order_number: "MC#{SecureRandom.hex(4).upcase}",
      user: @user,
      status: "processing",
      currency: "CNY",
      subtotal_cents: 1000,
      total_cents: 1000
    )
    @order_item = Commerce::OrderItem.create!(
      order: @order,
      product_name: "VIP",
      unit_price_cents: 1000,
      quantity: 1,
      total_cents: 1000,
      fulfillment_snapshot: {
        fulfillment_config: {
          commands: [ "give {player} diamond 1", "tell {uuid} thanks" ],
          server_id: "srv_test"
        }
      }
    )
    @fulfillment = Commerce::Fulfillment.create!(
      order: @order,
      order_item: @order_item,
      status: "pending"
    )
  end

  test "substitutes player and uuid placeholders" do
    profile = Minecraft::PlayerProfile.create!
    Minecraft::PlayerIdentity.create!(
      player_profile: profile,
      platform: "java",
      external_uuid: "550e8400-e29b-41d4-a716-446655440099",
      username: "Steve",
      identity_type: "primary",
      valid_from: Time.current
    )
    Minecraft::IdentityLink.create!(player_profile: profile, user: @user, linked_at: Time.current)

    result = Commerce::BuildConnectorTaskPayload.call(fulfillment: @fulfillment)

    assert result.success?
    assert_equal [ "give Steve diamond 1", "tell 550e8400-e29b-41d4-a716-446655440099 thanks" ], result.value[:commands]
    assert_equal @fulfillment.delivery_id, result.value[:delivery_id]
    assert_equal @order_item.id, result.value[:order_item_id]
  end

  test "fails when player is not linked and placeholders are present" do
    result = Commerce::BuildConnectorTaskPayload.call(fulfillment: @fulfillment)

    assert result.failure?
    assert_equal "player_not_linked", result.error
  end

  test "passes commands through when no placeholders are used" do
    @order_item.update!(
      fulfillment_snapshot: {
        fulfillment_config: {
          commands: [ "say hello world" ]
        }
      }
    )

    result = Commerce::BuildConnectorTaskPayload.call(fulfillment: @fulfillment)

    assert result.success?
    assert_equal [ "say hello world" ], result.value[:commands]
  end

  test "fails when commands are missing" do
    @order_item.update!(fulfillment_snapshot: { fulfillment_config: {} })

    result = Commerce::BuildConnectorTaskPayload.call(fulfillment: @fulfillment)

    assert result.failure?
    assert_equal "missing_commands", result.error
  end
end

class Minecraft::DispatchFulfillmentJobTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @server = Minecraft::Server.create!(
      public_id: "srv_dispatch_#{SecureRandom.hex(4)}",
      name: "Dispatch Server",
      connector_secret: "secret_#{SecureRandom.hex(8)}"
    )
    @order = Commerce::Order.create!(
      public_id: "ord_#{SecureRandom.alphanumeric(16)}",
      order_number: "MC#{SecureRandom.hex(4).upcase}",
      user: @user,
      status: "fulfilling",
      currency: "CNY",
      subtotal_cents: 1000,
      total_cents: 1000
    )
    @order_item = Commerce::OrderItem.create!(
      order: @order,
      product_name: "Coins",
      unit_price_cents: 1000,
      quantity: 1,
      total_cents: 1000,
      fulfillment_snapshot: {
        fulfillment_config: {
          commands: [ "eco give {player} 100" ],
          server_id: @server.public_id
        }
      }
    )
    @fulfillment = Commerce::Fulfillment.create!(
      order: @order,
      order_item: @order_item,
      status: "pending"
    )
    profile = Minecraft::PlayerProfile.create!
    Minecraft::PlayerIdentity.create!(
      player_profile: profile,
      platform: "java",
      external_uuid: "550e8400-e29b-41d4-a716-446655440088",
      username: "Buyer",
      identity_type: "primary",
      valid_from: Time.current
    )
    Minecraft::IdentityLink.create!(player_profile: profile, user: @user, linked_at: Time.current)
  end

  test "creates connector task with top-level commands" do
    assert_difference -> { Minecraft::ConnectorTask.count }, 1 do
      Minecraft::DispatchFulfillmentJob.perform_now(@fulfillment.id)
    end

    task = Minecraft::ConnectorTask.last
    assert_equal [ "eco give Buyer 100" ], task.payload["commands"]
    assert_equal @fulfillment.delivery_id, task.payload["delivery_id"]
  end

  test "marks fulfillment failed when server is missing" do
    @order_item.update!(
      fulfillment_snapshot: {
        fulfillment_config: {
          commands: [ "eco give {player} 100" ],
          server_id: "missing-server"
        }
      }
    )

    Minecraft::DispatchFulfillmentJob.perform_now(@fulfillment.id)

    assert_equal "failed", @fulfillment.reload.status
    assert_equal "server_not_found", @fulfillment.last_error
  end

  test "marks fulfillment failed when player is not linked" do
    Minecraft::IdentityLink.delete_all

    Minecraft::DispatchFulfillmentJob.perform_now(@fulfillment.id)

    assert_equal "failed", @fulfillment.reload.status
    assert_equal "player_not_linked", @fulfillment.last_error
  end

  test "reconciles fulfillment when connector task already completed" do
    Minecraft::ConnectorTask.create!(
      server: @server,
      fulfillment: @fulfillment,
      task_type: "deliver_item",
      delivery_id: @fulfillment.delivery_id,
      status: "completed",
      payload: { commands: [ "eco give Buyer 100" ] },
      completed_at: Time.current
    )

    assert_no_difference -> { Minecraft::ConnectorTask.count } do
      Minecraft::DispatchFulfillmentJob.perform_now(@fulfillment.id)
    end

    assert_equal "fulfilled", @fulfillment.reload.status
  end

  test "retries failed connector task on new server" do
    other_server = Minecraft::Server.create!(
      public_id: "srv_retry_#{SecureRandom.hex(4)}",
      name: "Retry Server",
      connector_secret: "secret_#{SecureRandom.hex(8)}"
    )
    @order_item.update!(
      fulfillment_snapshot: {
        fulfillment_config: {
          commands: [ "eco give {player} 100" ],
          server_id: other_server.public_id
        }
      }
    )
    task = Minecraft::ConnectorTask.create!(
      server: @server,
      fulfillment: @fulfillment,
      task_type: "deliver_item",
      delivery_id: @fulfillment.delivery_id,
      status: "failed",
      payload: { commands: [ "eco give Buyer 100" ] }
    )

    Minecraft::DispatchFulfillmentJob.perform_now(@fulfillment.id)

    task.reload
    assert_equal "pending", task.status
    assert_equal other_server.id, task.server.id
  end
end

class Commerce::FulfillOrderDownloadOnlyTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @order = Commerce::Order.create!(
      public_id: "ord_#{SecureRandom.alphanumeric(16)}",
      order_number: "MC#{SecureRandom.hex(4).upcase}",
      user: @user,
      status: "paid",
      currency: "CNY",
      subtotal_cents: 1000,
      total_cents: 1000
    )
    Commerce::OrderItem.create!(
      order: @order,
      product_name: "Download Pack",
      unit_price_cents: 1000,
      quantity: 1,
      total_cents: 1000,
      fulfillment_snapshot: {
        fulfillment_config: {
          download_url: "https://example.com/file.zip"
        }
      }
    )
  end

  test "marks download-only fulfillment fulfilled without dispatching minecraft job" do
    assert_no_enqueued_jobs(only: Minecraft::DispatchFulfillmentJob) do
      Commerce::FulfillOrderJob.perform_now(@order.id)
    end

    fulfillment = @order.fulfillments.first
    assert_equal "fulfilled", fulfillment.status
    assert_includes %w[fulfilled completed], @order.reload.status
  end
end

class Commerce::CompleteOrderPaymentAsyncTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @order = Commerce::Order.create!(
      public_id: "ord_#{SecureRandom.alphanumeric(16)}",
      order_number: "MC#{SecureRandom.hex(4).upcase}",
      user: @user,
      status: "paid",
      currency: "CNY",
      subtotal_cents: 1000,
      total_cents: 1000
    )
  end

  test "enqueues post-payment side effects and fulfill jobs" do
    assert_enqueued_with(job: Commerce::PostPaymentSideEffectsJob, args: [ @order.id ]) do
      assert_enqueued_with(job: Commerce::FulfillOrderJob, args: [ @order.id ]) do
        result = Commerce::CompleteOrderPayment.call(order: @order)
        assert result.success?
      end
    end
  end

  test "staff marked creates succeeded payment record for refunds" do
    assert_difference -> { Payments::Record.where(status: "succeeded").count }, 1 do
      result = Commerce::CompleteOrderPayment.call(order: @order, staff_marked: true)
      assert result.success?
    end

    payment = @order.payment_records.find_by!(provider: "fake", provider_payment_id: "staff-#{@order.public_id}")
    assert_equal @order.total_cents, payment.amount_cents
    assert payment.metadata["staff_marked"]
  end

  test "staff marked payment record is idempotent" do
    Commerce::CompleteOrderPayment.call(order: @order, staff_marked: true)

    assert_no_difference -> { Payments::Record.where(status: "succeeded").count } do
      Commerce::CompleteOrderPayment.call(order: @order, staff_marked: true)
    end
  end

  test "skips duplicate jobs when side effects completed and fulfillment started" do
    @order.update!(status: "processing")
    @order.events.create!(event_type: Commerce::PostPaymentSideEffectsJob::COMPLETED_EVENT, metadata: {})

    assert_no_enqueued_jobs(only: [ Commerce::PostPaymentSideEffectsJob, Commerce::FulfillOrderJob ]) do
      result = Commerce::CompleteOrderPayment.call(order: @order)
      assert result.success?
      assert result.value[:idempotent]
    end
  end

  test "re-enqueues post payment side effects when order processing but event missing" do
    @order.update!(status: "processing")

    assert_enqueued_with(job: Commerce::PostPaymentSideEffectsJob, args: [ @order.id ]) do
      assert_no_enqueued_jobs(only: Commerce::FulfillOrderJob) do
        result = Commerce::CompleteOrderPayment.call(order: @order)
        assert result.success?
        assert_not result.value[:idempotent]
      end
    end
  end

  test "does not re-enqueue fulfill job when enqueue event already recorded" do
    @order.events.create!(event_type: Commerce::CompleteOrderPayment::FULFILL_ORDER_ENQUEUED_EVENT, metadata: {})
    @order.events.create!(event_type: Commerce::PostPaymentSideEffectsJob::COMPLETED_EVENT, metadata: {})

    assert_no_enqueued_jobs(only: Commerce::FulfillOrderJob) do
      result = Commerce::CompleteOrderPayment.call(order: @order)
      assert result.success?
      assert result.value[:idempotent]
    end
  end
end

class Commerce::PostPaymentSideEffectsJobTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    NotificationPreference.set!(@user, channel: "in_app", notification_type: "commerce.payment_confirmed", enabled: true)
    @product = Commerce::Product.create!(
      public_id: "prod_#{SecureRandom.alphanumeric(16)}",
      name: "Side Effect Product",
      slug: "side-effect-#{SecureRandom.hex(4)}",
      price_cents: 500,
      currency: "CNY",
      status: "active",
      product_type: "digital"
    )
    @order = Commerce::Order.create!(
      public_id: "ord_#{SecureRandom.alphanumeric(16)}",
      order_number: "MC#{SecureRandom.hex(4).upcase}",
      user: @user,
      status: "paid",
      currency: "CNY",
      subtotal_cents: 500,
      total_cents: 500
    )
    Commerce::OrderItem.create!(
      order: @order,
      product: @product,
      product_name: @product.name,
      unit_price_cents: 500,
      quantity: 1,
      total_cents: 500,
      fulfillment_snapshot: {}
    )
  end

  test "runs payment confirmed notifications and community side effects" do
    assert_difference -> { Notification.where(notification_type: "commerce.payment_confirmed").count }, 1 do
      assert_enqueued_jobs 1, only: MailDeliveryJob do
        Commerce::PostPaymentSideEffectsJob.perform_now(@order.id)
      end
    end
  end

  test "is idempotent when performed twice" do
    Commerce::PostPaymentSideEffectsJob.perform_now(@order.id)

    assert Commerce::OrderEvent.exists?(order: @order, event_type: "post_payment_side_effects_completed")
    assert_no_difference -> { Notification.where(notification_type: "commerce.payment_confirmed").count } do
      assert_no_enqueued_jobs only: MailDeliveryJob do
        Commerce::PostPaymentSideEffectsJob.perform_now(@order.id)
      end
    end
  end

  test "skips side effects for refunded orders" do
    @order.update!(status: "refunded")

    assert_no_difference -> { Notification.where(notification_type: "commerce.payment_confirmed").count } do
      assert_no_enqueued_jobs only: MailDeliveryJob do
        Commerce::PostPaymentSideEffectsJob.perform_now(@order.id)
      end
    end
    assert_not Commerce::OrderEvent.exists?(order: @order, event_type: "post_payment_side_effects_completed")
  end
end

class Commerce::BulkUpdateOrdersMcGuardTest < ActiveSupport::TestCase
  setup do
    @admin = create_user
    @user = create_user
    @order = Commerce::Order.create!(
      public_id: "ord_#{SecureRandom.alphanumeric(16)}",
      order_number: "MC#{SecureRandom.hex(4).upcase}",
      user: @user,
      status: "paid",
      currency: "CNY",
      subtotal_cents: 1000,
      total_cents: 1000
    )
    Commerce::OrderItem.create!(
      order: @order,
      product_name: "MC Item",
      unit_price_cents: 1000,
      quantity: 1,
      total_cents: 1000,
      fulfillment_snapshot: {
        fulfillment_config: {
          commands: [ "give {player} diamond 1" ],
          server_id: "srv_test"
        }
      }
    )
  end

  test "rejects bulk mark fulfilled for minecraft connector orders" do
    result = Commerce::BulkUpdateOrders.call(
      actor: @admin,
      order_public_ids: [ @order.public_id ],
      action: "mark_fulfilled"
    )

    assert result.failure? || result.value[:failures].present?
    failure = result.value&.dig(:failures, 0) || { error: result.error }
    assert_match(/自动履约|游戏内发货/, failure[:error].to_s + result.error.to_s)
    assert_equal "paid", @order.reload.status
  end

  test "rejects bulk mark fulfilled for gift card orders" do
    gift_order = Commerce::Order.create!(
      public_id: "ord_#{SecureRandom.alphanumeric(16)}",
      order_number: "GC#{SecureRandom.hex(4).upcase}",
      user: @user,
      status: "paid",
      currency: "CNY",
      subtotal_cents: 500,
      total_cents: 500
    )
    Commerce::OrderItem.create!(
      order: gift_order,
      product_name: "Gift Card",
      unit_price_cents: 500,
      quantity: 1,
      total_cents: 500,
      fulfillment_snapshot: { product_type: "gift_card" }
    )

    result = Commerce::BulkUpdateOrders.call(
      actor: @admin,
      order_public_ids: [ gift_order.public_id ],
      action: "mark_fulfilled"
    )

    assert result.failure? || result.value[:failures].present?
    assert_equal "paid", gift_order.reload.status
  end

  test "rejects bulk mark fulfilled for membership orders" do
    membership_order = Commerce::Order.create!(
      public_id: "ord_#{SecureRandom.alphanumeric(16)}",
      order_number: "MBR#{SecureRandom.hex(4).upcase}",
      user: @user,
      status: "paid",
      currency: "CNY",
      subtotal_cents: 3000,
      total_cents: 3000
    )
    Commerce::OrderItem.create!(
      order: membership_order,
      product_name: "VIP Monthly",
      unit_price_cents: 3000,
      quantity: 1,
      total_cents: 3000,
      fulfillment_snapshot: { product_type: "membership", membership_type_id: 1 }
    )

    result = Commerce::BulkUpdateOrders.call(
      actor: @admin,
      order_public_ids: [ membership_order.public_id ],
      action: "mark_fulfilled"
    )

    assert result.failure? || result.value[:failures].present?
    assert_equal "paid", membership_order.reload.status
  end
end

class Commerce::WebhookAsyncEnqueueTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @order = Commerce::Order.create!(
      public_id: "ord_webhook_async",
      order_number: "ORD-WH-ASYNC",
      user: @user,
      status: "pending",
      subtotal_cents: 1000,
      total_cents: 1000,
      discount_cents: 0,
      currency: "CNY"
    )
    Payments::Record.create!(
      order: @order,
      provider: "fake",
      status: "pending",
      amount_cents: 1000,
      currency: "CNY",
      provider_payment_id: "fake_pay_async"
    )
  end

  test "webhook endpoint enqueues processor job and returns ok" do
    payload = { payment_id: "fake_pay_async" }.to_json
    signature = OpenSSL::HMAC.hexdigest("SHA256", "fake_webhook_secret", payload)

    assert_enqueued_with(job: Payments::ProcessWebhookJob) do
      post store_webhook_path(provider: "fake"),
        params: payload,
        headers: {
          "CONTENT_TYPE" => "application/json",
          "X-Webhook-Signature" => signature
        }
    end

    assert_response :ok
  end
end
