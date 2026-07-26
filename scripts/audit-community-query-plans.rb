#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../config/environment"

report = Operations::CommunityQueryPlanAudit.call

puts JSON.pretty_generate(report)
