# frozen_string_literal: true

require "test_helper"

module Payments
  class FakeScenariosTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      @user = create_user
      @order = Commerce::Order.create!(
        public_id: "ord_fake_scenario_#{SecureRandom.hex(4)}",
        order_number: "ORD-DEV-#{SecureRandom.hex(4).upcase}",
        user: @user,
        status: "pending",
        subtotal_cents: 1_000,
        total_cents: 1_000,
        discount_cents: 0,
        currency: "CNY"
      )
    end

    test "failure and cancellation scenarios stay unavailable outside Developer Mode" do
      payment = create_payment

      result = with_developer_mode(enabled: false) do
        Payments::RunFakeScenario.call(
          payment_record: payment,
          scenario: "failure",
          actor: @user
        )
      end

      assert_predicate result, :failure?
      assert_equal "fake_payment_scenario_unavailable", result.code
      assert_equal "pending", payment.reload.status
    end

    test "failure and cancellation scenarios produce explicit terminal attempts" do
      failure = with_developer_mode do
        Payments::RunFakeScenario.call(
          payment_record: create_payment,
          scenario: "failure",
          actor: @user
        )
      end
      cancellation = with_developer_mode do
        Payments::RunFakeScenario.call(
          payment_record: create_payment,
          scenario: "cancellation",
          actor: @user
        )
      end

      assert_predicate failure, :success?
      assert_equal "failed",
        failure.value.fetch(:payment_record).reload.status
      assert_predicate cancellation, :success?
      assert_equal "cancelled",
        cancellation.value.fetch(:payment_record).reload.status
    end

    test "delayed scenario enqueues one guarded completion" do
      payment = create_payment

      with_developer_mode do
        assert_enqueued_with(
          job: Payments::CompleteFakePaymentJob,
          args: [ payment.id ]
        ) do
          result = Payments::RunFakeScenario.call(
            payment_record: payment,
            scenario: "delayed",
            actor: @user
          )
          assert_predicate result, :success?
          assert_equal true, result.value.fetch(:delayed)
        end
      end

      assert_equal "pending", payment.reload.status
      assert_equal "delayed",
        payment.metadata.fetch("developer_mode_scenario")

      assert_no_enqueued_jobs do
        with_developer_mode do
          result = Payments::RunFakeScenario.call(
            payment_record: payment,
            scenario: "delayed",
            actor: @user
          )
          assert_predicate result, :success?
        end
      end

      travel 11.seconds do
        with_developer_mode do
          Payments::CompleteFakePaymentJob.perform_now(payment.id)
        end
      end
      assert_equal "succeeded", payment.reload.status
      assert_equal "paid", @order.reload.status
    end

    private

    def create_payment
      Payments::Record.create!(
        order: @order,
        provider: "fake",
        provider_payment_id: "fake_#{SecureRandom.hex(8)}",
        status: "pending",
        amount_cents: 1_000,
        currency: "CNY"
      )
    end

    def with_developer_mode(enabled: true)
      settings = Mcweb::DeveloperMode.parse(
        config: {
          developer_mode: {
            enabled: enabled,
            integrations: {
              payments: enabled ? "fake" : "inherit"
            }
          }
        },
        environment: {}
      )
      previous =
        Mcweb::DeveloperMode.instance_variable_get(:@settings)
      Mcweb::DeveloperMode.instance_variable_set(:@settings, settings)
      yield
    ensure
      Mcweb::DeveloperMode.instance_variable_set(:@settings, previous)
    end
  end
end
