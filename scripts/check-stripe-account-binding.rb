#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../config/environment"

result = Payments::StripeAccountBindingPreflight.call
payload = {
  ok: result.success?,
  code: result.code,
  account_bound: result.value.to_h[:account_bound],
  financial_history_present:
    result.value.to_h[:financial_history_present],
  provider_enabled: result.value.to_h[:provider_enabled]
}.compact

puts JSON.generate(payload)
exit(result.success? ? 0 : 1)
