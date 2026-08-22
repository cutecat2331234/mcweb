#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require_relative "../lib/mcweb/disaster_recovery/backup_retention"

begin
  options = {}
  OptionParser.new do |parser|
    parser.on("--root PATH") { |value| options[:root] = value }
  end.parse!(ARGV)
  raise Mcweb::DisasterRecovery::BackupRetention::Error, "backup_retention_argument_invalid" if ARGV.any?

  retention = Mcweb::DisasterRecovery::BackupRetention.new(
    root: options.fetch(:root),
    retention_days: ENV.fetch("MCWEB_BACKUP_RETENTION_DAYS", "30"),
    retention_count: ENV.fetch("MCWEB_BACKUP_RETENTION_COUNT", "7")
  )
  pruned = retention.prune!
  puts "Backup retention completed: pruned_count=#{pruned.size}"
rescue KeyError, OptionParser::ParseError
  warn "Backup retention failed: backup_retention_argument_invalid"
  exit 64
rescue Mcweb::DisasterRecovery::BackupRetention::Error => error
  warn "Backup retention failed: #{error.code}"
  exit 70
rescue Mcweb::DisasterRecovery::ObjectArchive::Error => error
  warn "Backup retention failed: #{error.code}"
  exit 70
rescue Aws::Errors::ServiceError => error
  warn "Backup retention failed: object_store_unavailable (#{error.class.name})"
  exit 69
rescue StandardError => error
  warn "Backup retention failed: backup_retention_internal_error (#{error.class.name})"
  exit 70
end
