# frozen_string_literal: true

module Minecraft
  class DispatchFulfillmentJob < ApplicationJob
    queue_as :minecraft

    def perform(fulfillment_id)
      fulfillment = Commerce::Fulfillment.find_by(id: fulfillment_id)
      return unless fulfillment&.pending?
      return unless fulfillment.retryable?
      return if fulfillment.next_attempt_at.present? && fulfillment.next_attempt_at.future?

      order = fulfillment.order
      return if order.refunded? || order.cancelled?

      provider_id = plugin_provider_id(fulfillment)
      if provider_id.present?
        dispatch_plugin_provider!(fulfillment, provider_id)
        return
      end

      existing = Minecraft::ConnectorTask.find_by(fulfillment: fulfillment)
      if existing&.completed?
        reconcile_completed_fulfillment!(fulfillment)
        return
      end

      if Minecraft::ConnectorTask.where(fulfillment: fulfillment, status: %w[pending claimed]).exists?
        return
      end

      order_item = fulfillment.order_item
      snapshot = order_item.fulfillment_snapshot || {}
      config = snapshot["fulfillment_config"] || snapshot[:fulfillment_config] || {}
      server_public_id = config["server_id"] || config[:server_id] || config["minecraft_server_id"] || config[:minecraft_server_id]

      server =
        if server_public_id.present?
          Minecraft::Server.find_by(public_id: server_public_id.to_s) ||
            Minecraft::Server.find_by(id: server_public_id.to_i)
        end

      unless server
        Rails.logger.error("[DispatchFulfillmentJob] No Minecraft server found for fulfillment #{fulfillment_id} (server_id=#{server_public_id.inspect})")
        record_dispatch_failure!(fulfillment, "server_not_found")
        return
      end

      if maintenance_blocks_fulfillment?(server)
        Rails.logger.info("[DispatchFulfillmentJob] Deferred fulfillment #{fulfillment_id} — server in maintenance")
        Minecraft::DispatchFulfillmentJob.set(wait: 10.minutes).perform_later(fulfillment_id)
        return
      end

      payload_result = Commerce::BuildConnectorTaskPayload.call(fulfillment: fulfillment)
      unless payload_result.success?
        record_dispatch_failure!(fulfillment, payload_result.code || payload_result.error)
        return
      end

      task_payload = payload_result.value
      task_type = config["task_type"] || config[:task_type] || "deliver_item"
      Commerce::Fulfillment.transaction do
        fulfillment.lock!
        return unless fulfillment.pending? && fulfillment.retryable?

        fulfillment.begin_dispatch_attempt!
        existing = Minecraft::ConnectorTask.lock.find_by(fulfillment: fulfillment)
        if existing
          return unless existing.failed?

          existing.update!(
            server: server,
            status: "pending",
            claimed_at: nil,
            completed_at: nil,
            result: {},
            payload: task_payload,
            task_type: task_type
          )
        else
          Minecraft::ConnectorTask.create!(
            server: server,
            fulfillment: fulfillment,
            task_type: task_type,
            delivery_id: fulfillment.delivery_id,
            status: "pending",
            payload: task_payload
          )
        end
      end
    rescue ActiveRecord::RecordNotUnique
      # A concurrent dispatch won the connector-task or attempt insert. Its
      # delivery id remains the single source of idempotency.
      nil
    end

    private

    def dispatch_plugin_provider!(fulfillment, provider_id)
      fulfillment.reload
      return unless fulfillment.pending? && fulfillment.retryable?

      attempt = fulfillment.begin_dispatch_attempt!

      result = Mcweb::Plugins.dispatch_fulfillment(
        provider_id:,
        request: plugin_provider_request(
          fulfillment.reload,
          attempt: attempt.reload,
          provider_id:
        )
      )

      case result.fetch("status")
      when "succeeded"
        fulfillment.mark_fulfilled!(attempt:, result:)
        Commerce::SyncOrderFulfillmentStatusJob.perform_later(fulfillment.store_order_id)
      when "retryable"
        fulfillment.mark_failed!(
          error: result.fetch("error_code"),
          attempt:,
          result:,
          retryable: true
        )
      when "failed"
        fulfillment.mark_failed!(
          error: result.fetch("error_code"),
          attempt:,
          result:,
          retryable: false
        )
      end
    rescue Mcweb::Plugins::FulfillmentProviderError => error
      return unless attempt

      terminal = %w[provider_invalid provider_response_invalid].include?(error.code)
      fulfillment.mark_failed!(
        error: error.code,
        attempt:,
        result: { status: terminal ? "failed" : "retryable", error_code: error.code },
        retryable: !terminal
      )
    rescue ActiveRecord::RecordInvalid, ActiveRecord::StaleObjectError
      # A concurrent recovery or cancellation owns the terminal state.
      nil
    end

    def plugin_provider_id(fulfillment)
      config = fulfillment_config(fulfillment)
      config["plugin_provider"].presence || config["fulfillment_provider"].presence
    end

    def fulfillment_config(fulfillment)
      snapshot = fulfillment.order_item.fulfillment_snapshot || {}
      (snapshot["fulfillment_config"] || snapshot[:fulfillment_config] || {}).with_indifferent_access
    end

    def plugin_provider_request(fulfillment, attempt:, provider_id:)
      item = fulfillment.order_item
      order = fulfillment.order
      product = item.product
      variant = item.variant
      config = fulfillment_config(fulfillment)

      {
        schema_version: "1",
        provider_id:,
        delivery_id: fulfillment.delivery_id,
        attempt: {
          number: attempt.attempt_number,
          idempotency_key: attempt.idempotency_key
        },
        order: {
          public_id: order.public_id,
          status: order.status,
          currency: order.currency,
          total_cents: order.total_cents
        },
        item: {
          id: item.id,
          product_public_id: product&.public_id,
          variant_id: variant&.id,
          product_name: item.product_name,
          variant_name: item.variant_name,
          quantity: item.quantity,
          unit_price_cents: item.unit_price_cents,
          total_cents: item.total_cents
        },
        options: config["provider_options"].is_a?(Hash) ? config["provider_options"] : {}
      }
    end

    def reconcile_completed_fulfillment!(fulfillment)
      return if fulfillment.fulfilled?

      fulfillment.mark_fulfilled!(
        result: {
          success: true,
          status: "completed",
          external_reference: fulfillment.delivery_id
        }
      )
      Commerce::SyncOrderFulfillmentStatusJob.perform_later(fulfillment.store_order_id)
    end

    def record_dispatch_failure!(fulfillment, error)
      attempt = fulfillment.begin_dispatch_attempt!
      fulfillment.mark_failed!(error: error, attempt: attempt)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::StaleObjectError
      fulfillment.reload
      fulfillment.mark_failed!(error: error) unless fulfillment.failed? || fulfillment.cancelled?
    end

    def maintenance_blocks_fulfillment?(server)
      return false unless Minecraft::MaintenanceActive.pause_fulfillment?

      Minecraft::MaintenanceActive.call(server: server).value[:active]
    end
  end
end
