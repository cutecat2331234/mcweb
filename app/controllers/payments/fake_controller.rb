# frozen_string_literal: true

module Payments
  class FakeController < ApplicationController
    before_action :ensure_fake_payments_allowed!
    before_action :require_login
    before_action :set_payment

    def show
      order = @payment.order
      return redirect_to root_path, alert: t("mcweb.flash.payment_access_denied") unless order.user_id == current_user.id
      unless order.payable?
        message = order.payment_expired? ?
          t("mcweb.flash.payment_expired") :
          t("mcweb.flash.payment_unavailable")
        return redirect_to store_order_path(order), alert: message
      end

      begin_result = Commerce::BeginOrderPayment.call(order: order)
      unless begin_result.success?
        return redirect_to store_order_path(order), alert: service_error_message(begin_result)
      end

      if @payment.status == "pending" && @payment.amount_cents != order.total_cents
        @payment.mark_failed!
        return redirect_to store_order_path(order), alert: t("mcweb.flash.payment_expired")
      end

      render inertia: "Payments/Fake/Show", props: {
        paymentId: @payment.provider_payment_id,
        amountLabel: format_money(@payment.amount_cents, @payment.currency),
        order: {
          id: order.public_id,
          order_number: order.order_number,
          url: store_order_path(order)
        },
        payUrl: fake_payment_path(@payment.provider_payment_id),
        developerScenarios: developer_scenarios_enabled?
      }
    end

    def create
      order = @payment.order
      return redirect_to root_path, alert: t("mcweb.flash.payment_access_denied") unless order.user_id == current_user.id
      unless order.payable?
        message = order.payment_expired? ?
          t("mcweb.flash.payment_expired") :
          t("mcweb.flash.payment_unavailable")
        return redirect_to store_order_path(order), alert: message
      end

      if @payment.status == "pending" && @payment.amount_cents != order.total_cents
        @payment.mark_failed!
        return redirect_to store_order_path(order), alert: t("mcweb.flash.payment_expired")
      end

      scenario = developer_scenarios_enabled? ?
        params[:scenario].to_s.presence || "success" :
        "success"
      result = Payments::RunFakeScenario.call(
        payment_record: @payment,
        scenario: scenario,
        actor: current_user
      )

      if result.success?
        redirect_to store_order_path(order),
          notice: fake_scenario_notice(scenario)
      else
        redirect_to fake_payment_path(@payment.provider_payment_id), alert: service_error_message(result)
      end
    end

    private

    def set_payment
      @payment = Payments::Record.find_by!(provider: "fake", provider_payment_id: params[:id])
    end

    def ensure_fake_payments_allowed!
      return if Payments::Provider.known?("fake")

      head :not_found
    end

    def developer_scenarios_enabled?
      Mcweb::DeveloperMode.enabled? &&
        Mcweb::DeveloperMode.integration(:payments) == :fake
    end

    def fake_scenario_notice(scenario)
      key =
        case scenario
        when "failure" then "developer_fake_payment_failed"
        when "cancellation" then "developer_fake_payment_cancelled"
        when "delayed" then "developer_fake_payment_delayed"
        else "payment_success"
        end
      t("mcweb.flash.#{key}")
    end
  end
end
