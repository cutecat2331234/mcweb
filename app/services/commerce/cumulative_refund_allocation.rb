# frozen_string_literal: true

module Commerce
  module CumulativeRefundAllocation
    module_function

    # Allocations are calculated from the cumulative refunded amount, rather
    # than from each refund independently. Integer half-up rounding avoids
    # floating-point drift and guarantees that the final allocation is exact.
    def target(total_units:, refunded_cents:, payment_cents:)
      total_units = total_units.to_i
      payment_cents = payment_cents.to_i
      return 0 unless total_units.positive? && payment_cents.positive?

      refunded_cents = refunded_cents.to_i.clamp(0, payment_cents)
      numerator = total_units * refunded_cents
      ((2 * numerator) + payment_cents) / (2 * payment_cents)
    end
  end
end
