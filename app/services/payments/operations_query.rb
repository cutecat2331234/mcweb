# frozen_string_literal: true

module Payments
  class OperationsQuery
    VIEWS = %w[payments webhooks orphans refunds].freeze
    WEBHOOK_STALE_AFTER = Payments::WebhookEvent::PROCESSING_TIMEOUT
    MAX_QUERY_LENGTH = 100

    attr_reader :view

    def initialize(view:, provider: nil, status: nil, provider_status: nil, query: nil)
      @view = VIEWS.include?(view.to_s) ? view.to_s : "payments"
      @provider = provider.to_s.strip.first(80).presence
      @status = status.to_s.strip.first(32).presence
      @provider_status = provider_status.to_s.strip.first(80).presence
      @query = query.to_s.strip.first(MAX_QUERY_LENGTH).presence
    end

    def relation
      case view
      when "webhooks" then webhook_relation
      when "orphans" then payment_relation(orphans_only: true)
      when "refunds" then refund_relation
      else payment_relation
      end
    end

    def filter_options
      {
        providers: providers,
        statuses: statuses_for_view,
        provider_statuses: refund_provider_statuses
      }
    end

    def filters
      {
        provider: @provider,
        status: @status,
        provider_status: @provider_status,
        q: @query
      }
    end

    def summary
      {
        payments: {
          total: Payments::Record.count,
          failed: Payments::Record.failed.count,
          processing: Payments::Record.processing.count
        },
        webhooks: {
          total: Payments::WebhookEvent.count,
          failed: Payments::WebhookEvent.failed.count,
          processing: Payments::WebhookEvent.processing.count,
          stale: self.class.stale_webhooks.count,
          retry_scheduled: Payments::WebhookEvent.failed.where.not(next_retry_at: nil).count,
          dead_letter: Payments::WebhookEvent.dead_letter.count
        },
        orphans: {
          total: orphan_scope(Payments::Record.all).count
        },
        refunds: {
          total: Commerce::Refund.count,
          failed: Commerce::Refund.failed.count,
          processing: Commerce::Refund.in_flight.count,
          stale: Commerce::Refund.stale_processing.count
        }
      }
    end

    def provider_statuses
      configs = Payments::ProviderConfig.all.index_by(&:provider)
      payment_counts = Payments::Record.group(:provider, :status).count
      refund_counts = Commerce::Refund
        .joins(:payment_record)
        .where.not(provider_status: [ nil, "" ])
        .group("payment_records.provider", "store_refunds.provider_status")
        .count

      providers.map do |provider|
        config = configs[provider]
        {
          provider: provider,
          configured: config.present?,
          enabled: config&.enabled? || false,
          checkout_ready: checkout_ready?(config),
          payment_counts: counts_for(payment_counts, provider),
          refund_counts: counts_for(refund_counts, provider),
          updated_at: config&.updated_at
        }
      end
    end

    def self.stale_webhooks
      Payments::WebhookEvent
        .where(status: %w[received processing])
        .where(
          "COALESCE(processing_started_at, updated_at) < ?",
          WEBHOOK_STALE_AFTER.ago
        )
    end

    private

    def payment_relation(orphans_only: false)
      scope = Payments::Record.joins(:order).includes(:order)
      scope = orphan_scope(scope) if orphans_only
      scope = scope.where(provider: @provider) if @provider
      scope = scope.where(status: @status) if Payments::Record.statuses.key?(@status)
      scope = apply_payment_query(scope)
      scope.order(created_at: :desc)
    end

    def webhook_relation
      scope = Payments::WebhookEvent.all
      scope = scope.where(provider: @provider) if @provider
      scope = if @status == "stale"
        scope.where(id: self.class.stale_webhooks.select(:id))
      elsif Payments::WebhookEvent.statuses.key?(@status)
        scope.where(status: @status)
      else
        scope
      end
      if @query
        needle = search_needle
        scope = scope.where(
          "payment_webhook_events.event_id ILIKE :needle OR payment_webhook_events.event_type ILIKE :needle",
          needle: needle
        )
      end
      scope.order(created_at: :desc)
    end

    def refund_relation
      scope = Commerce::Refund.joins(:payment_record, :order).includes(:payment_record, :order)
      scope = scope.where(payment_records: { provider: @provider }) if @provider
      scope = if @status == "stale"
        scope.where(id: Commerce::Refund.stale_processing.select(:id))
      elsif Commerce::Refund.statuses.key?(@status)
        scope.where(status: @status)
      else
        scope
      end
      scope = scope.where(provider_status: @provider_status) if @provider_status
      scope = apply_refund_query(scope)
      scope.order(created_at: :desc)
    end

    def apply_payment_query(scope)
      return scope unless @query

      scope.where(
        <<~SQL.squish,
          store_orders.order_number ILIKE :needle
          OR payment_records.provider_payment_id ILIKE :needle
          OR CAST(payment_records.id AS TEXT) = :exact
        SQL
        needle: search_needle,
        exact: @query
      )
    end

    def apply_refund_query(scope)
      return scope unless @query

      scope.where(
        <<~SQL.squish,
          store_orders.order_number ILIKE :needle
          OR store_refunds.provider_refund_id ILIKE :needle
          OR CAST(store_refunds.id AS TEXT) = :exact
        SQL
        needle: search_needle,
        exact: @query
      )
    end

    def orphan_scope(scope)
      scope.where("payment_records.metadata ->> 'orphaned' = ?", "true")
    end

    def providers
      @providers ||= begin
        configured = Payments::ProviderConfig.distinct.pluck(:provider)
        payments = Payments::Record.distinct.pluck(:provider)
        refunds = Commerce::Refund.joins(:payment_record).distinct.pluck("payment_records.provider")
        (configured | payments | refunds).compact.sort
      end
    end

    def statuses_for_view
      case view
      when "webhooks"
        Payments::WebhookEvent.statuses.keys + [ "stale" ]
      when "refunds"
        Commerce::Refund.statuses.keys + [ "stale" ]
      else
        Payments::Record.statuses.keys
      end
    end

    def refund_provider_statuses
      return [] unless view == "refunds"

      Commerce::Refund
        .where.not(provider_status: [ nil, "" ])
        .distinct
        .order(:provider_status)
        .pluck(:provider_status)
    end

    def counts_for(counts, provider)
      counts.each_with_object({}) do |((count_provider, status), count), values|
        values[status] = count if count_provider == provider
      end
    end

    def checkout_ready?(config)
      config&.checkout_ready? || false
    rescue Lockbox::DecryptionError
      false
    end

    def search_needle
      "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
    end
  end
end
