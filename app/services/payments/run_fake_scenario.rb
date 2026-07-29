# frozen_string_literal: true

module Payments
  class RunFakeScenario < ApplicationService
    SCENARIOS = %w[success failure cancellation delayed].freeze
    DELAY = 10.seconds

    def initialize(payment_record:, scenario:, actor: nil, now: Time.current)
      @payment_record = payment_record
      @scenario = scenario.to_s.presence || "success"
      @actor = actor
      @now = now
    end

    def call
      return invalid_scenario unless SCENARIOS.include?(@scenario)
      return unavailable unless @payment_record.provider == "fake"
      if @scenario != "success" && !developer_scenarios_enabled?
        return unavailable
      end

      result =
        case @scenario
        when "success"
          Commerce::ConfirmPayment.call(
            payment_record: @payment_record,
            provider_payment_id: @payment_record.provider_payment_id
          )
        when "failure"
          transition!("failed")
        when "cancellation"
          transition!("cancelled")
        when "delayed"
          schedule_delayed_completion
        end
      return result if result.failure?

      Administration::AuditLogger.call(
        actor: @actor,
        action: "developer_mode.fake_payment_scenario",
        resource: @payment_record,
        metadata: {
          scenario: @scenario,
          payment_status: @payment_record.reload.status
        }
      )
      ServiceResult.success(
        payment_record: @payment_record,
        scenario: @scenario,
        delayed: @scenario == "delayed"
      )
    end

    private

    def developer_scenarios_enabled?
      Mcweb::DeveloperMode.enabled? &&
        Mcweb::DeveloperMode.integration(:payments) == :fake
    end

    def transition!(status)
      if status == "failed"
        metadata = {
          "developer_mode_scenario" => @scenario,
          "developer_mode_scenario_at" => @now.iso8601
        }
        transitioned = @payment_record.mark_failed!(metadata:)
        unless transitioned
          return ServiceResult.failure(
            error: "fake_payment_not_pending",
            code: "fake_payment_not_pending"
          )
        end
        return ServiceResult.success(payment_record: @payment_record)
      end

      @payment_record.with_lock do
        unless @payment_record.pending? || @payment_record.processing?
          return ServiceResult.failure(
            error: "fake_payment_not_pending",
            code: "fake_payment_not_pending"
          )
        end

        metadata = @payment_record.metadata.to_h.merge(
          "developer_mode_scenario" => @scenario,
          "developer_mode_scenario_at" => @now.iso8601
        )
        @payment_record.update!(status:, metadata:)
      end
      ServiceResult.success(payment_record: @payment_record)
    end

    def schedule_delayed_completion
      scheduled = false
      @payment_record.with_lock do
        unless @payment_record.pending? || @payment_record.processing?
          return ServiceResult.failure(
            error: "fake_payment_not_pending",
            code: "fake_payment_not_pending"
          )
        end

        existing_schedule =
          @payment_record.metadata.to_h[
            "developer_mode_scheduled_for"
          ]
        if @payment_record.metadata.to_h[
            "developer_mode_scenario"
          ] == "delayed" && existing_schedule.present?
          return ServiceResult.success(
            payment_record: @payment_record,
            already_scheduled: true
          )
        end

        @payment_record.update!(
          metadata: @payment_record.metadata.to_h.merge(
            "developer_mode_scenario" => "delayed",
            "developer_mode_scenario_at" => @now.iso8601,
            "developer_mode_scheduled_for" =>
              DELAY.since(@now).iso8601
          )
        )
        scheduled = true
      end
      if scheduled
        Payments::CompleteFakePaymentJob
          .set(wait: DELAY)
          .perform_later(@payment_record.id)
      end
      ServiceResult.success(payment_record: @payment_record)
    end

    def invalid_scenario
      ServiceResult.failure(
        error: "fake_payment_scenario_invalid",
        code: "fake_payment_scenario_invalid"
      )
    end

    def unavailable
      ServiceResult.failure(
        error: "fake_payment_scenario_unavailable",
        code: "fake_payment_scenario_unavailable"
      )
    end
  end
end
