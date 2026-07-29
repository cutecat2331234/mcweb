# frozen_string_literal: true

require "mcweb/error_reporting"

Rails.error.subscribe(Mcweb::ErrorReporting.subscriber)
