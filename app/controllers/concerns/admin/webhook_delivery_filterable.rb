# frozen_string_literal: true

module Admin
  module WebhookDeliveryFilterable
    extend ActiveSupport::Concern

  private

    def webhook_filter_params
      {
        status: params[:status].presence,
        event: params[:event].presence,
        kind: params[:kind].presence,
        created_from: params[:created_from].presence,
        created_to: params[:created_to].presence
      }.compact
    end

    def apply_webhook_date_scope(scope)
      if params[:created_from].present?
        from = Time.zone.parse(params[:created_from].to_s) rescue nil
        scope = scope.where("created_at >= ?", from.beginning_of_day) if from
      end
      if params[:created_to].present?
        to = Time.zone.parse(params[:created_to].to_s) rescue nil
        scope = scope.where("created_at <= ?", to.end_of_day) if to
      end
      scope
    end

    def apply_webhook_kind_scope(scope)
      case params[:kind].to_s
      when "test"
        scope.where("request_payload @> ?", { test: true }.to_json)
      when "production"
        scope.where("NOT (request_payload @> ?)", { test: true }.to_json)
      else
        scope
      end
    end

    def webhook_date_filter_props
      {
        created_from: params[:created_from].to_s,
        created_to: params[:created_to].to_s,
        action: request.path
      }
    end
  end
end
