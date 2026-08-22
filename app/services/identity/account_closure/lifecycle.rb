# frozen_string_literal: true

module Identity
  module AccountClosure
    class Lifecycle < ApplicationService
      def initialize(context:, entries: AccountClosureCatalog.entries, finalize: nil)
        @context = context
        @entries = Array(entries)
        @finalize = finalize
      end

      def call
        preflights = run_preflights
        blocked = preflights.find { |_key, result| result.blocked? }
        if blocked
          return failure(
            "account_close_preflight_blocked",
            contributions: public_results(preflights)
          )
        end

        run_executions(preflights)
      rescue InvalidContribution => error
        Rails.logger.error(
          "[identity.account_closure] invalid_contribution phase=#{error.phase} key=#{error.key}"
        )
        failure("account_close_contributor_failed", contributions: error.results)
      rescue StandardError => error
        Rails.logger.error(
          "[identity.account_closure] lifecycle_failed error=#{error.class}"
        )
        failure("account_close_contributor_failed", contributions: {})
      end

      private

      def run_preflights
        @entries.each_with_object({}) do |entry, results|
          contribution = entry.contributor.preflight(context: @context)
          unless contribution.is_a?(Contribution) && (contribution.ready? || contribution.blocked?)
            raise InvalidContribution.new(
              phase: "preflight",
              key: entry.key,
              results: public_results(results)
            )
          end
          results[entry.key] = contribution
        rescue StandardError => error
          raise error if error.is_a?(InvalidContribution)

          results[entry.key] = Contribution.failed(code: "preflight_failed")
          raise InvalidContribution.new(
            phase: "preflight",
            key: entry.key,
            results: public_results(results)
          )
        end
      end

      def run_executions(preflights)
        executions = {}
        executed = []

        @entries.each do |entry|
          contribution = entry.contributor.execute(
            context: @context,
            preflight: preflights.fetch(entry.key)
          )
          unless contribution.is_a?(Contribution) && contribution.completed?
            executions[entry.key] = if contribution.is_a?(Contribution)
              contribution
            else
              Contribution.failed(code: "execution_contract_invalid")
            end
            raise ExecutionFailed.new(entry:, executions:, executed:)
          end

          executions[entry.key] = contribution
          executed << [ entry, contribution ]
        rescue StandardError => error
          raise error if error.is_a?(ExecutionFailed)

          executions[entry.key] = Contribution.failed(code: "execution_failed")
          raise ExecutionFailed.new(entry:, executions:, executed:)
        end

        contributions = public_results(executions)
        if @finalize
          begin
            finalized = @finalize.call(contributions.deep_dup)
            unless finalized.is_a?(Hash)
              raise ArgumentError, "account_closure_finalizer_result_invalid"
            end
            contributions = finalized.deep_stringify_keys
          rescue StandardError => error
            Rails.logger.error(
              "[identity.account_closure] finalization_failed error=#{error.class}"
            )
            executions["identity.finalization"] = Contribution.failed(
              code: "finalization_failed"
            )
            finalizer_entry = AccountClosureRegistry::Entry.new(
              key: "identity.finalization",
              contributor: nil
            )
            raise ExecutionFailed.new(
              entry: finalizer_entry,
              executions:,
              executed:
            )
          end
        end

        ServiceResult.success(contributions:)
      rescue ExecutionFailed => error
        compensations = compensate(error.executed)
        results = public_results(error.executions)
        results["compensations"] = compensations
        failure("account_close_contributor_failed", contributions: results)
      end

      def compensate(executed)
        executed.reverse_each.each_with_object({}) do |(entry, execution), results|
          compensation = entry.contributor.compensate(
            context: @context,
            execution:
          )
          unless compensation.is_a?(Contribution) && compensation.status == "compensated"
            compensation = Contribution.failed(code: "compensation_contract_invalid")
          end
          results[entry.key] = compensation.public_payload
        rescue StandardError => error
          Rails.logger.error(
            "[identity.account_closure] compensation_failed key=#{entry.key} error=#{error.class}"
          )
          results[entry.key] = Contribution.failed(code: "compensation_failed").public_payload
        end
      end

      def public_results(results)
        results.transform_values(&:public_payload)
      end

      def failure(code, contributions:)
        ServiceResult.failure(
          error: code,
          code:,
          value: { contributions: }
        )
      end

      class InvalidContribution < StandardError
        attr_reader :phase, :key, :results

        def initialize(phase:, key:, results:)
          @phase = phase
          @key = key
          @results = results
          super("#{phase}:#{key}")
        end
      end

      class ExecutionFailed < StandardError
        attr_reader :entry, :executions, :executed

        def initialize(entry:, executions:, executed:)
          @entry = entry
          @executions = executions
          @executed = executed
          super(entry.key)
        end
      end
    end
  end
end
