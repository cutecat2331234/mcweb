# frozen_string_literal: true

require "digest"
require "json"
require "openssl"

class HardenPluginJobPayloadDigests < ActiveRecord::Migration[8.0]
  PAYLOAD_DIGEST_VERSION = 2
  PAYLOAD_DIGEST_DOMAIN = "mcweb:plugin-job:payload-digest:v2\0".b.freeze
  MAX_WAIT_SECONDS = 31_536_000

  class MigrationPluginJobRun < ActiveRecord::Base
    self.table_name = "plugin_job_runs"

    has_encrypted :arguments,
      type: :json,
      encrypted_attribute: :encrypted_arguments
  end

  def up
    add_column :plugin_job_runs, :requested_wait_seconds, :integer
    add_column :plugin_job_runs, :payload_digest_version, :integer
    MigrationPluginJobRun.reset_column_information

    digest_key = payload_digest_key
    MigrationPluginJobRun.find_each do |record|
      wait_seconds = recover_wait_seconds!(record)
      canonical = canonical_payload(record, wait_seconds)
      hmac = OpenSSL::HMAC.hexdigest(
        "SHA256",
        digest_key,
        PAYLOAD_DIGEST_DOMAIN + canonical.b
      )
      record.update_columns(
        requested_wait_seconds: wait_seconds,
        payload_digest_version: PAYLOAD_DIGEST_VERSION,
        payload_digest: hmac
      )
      record.reload
      unless record.payload_digest == hmac &&
          record.payload_digest_version == PAYLOAD_DIGEST_VERSION
        raise "plugin job payload digest migration verification failed for row #{record.id}"
      end
    end

    change_column_null :plugin_job_runs, :requested_wait_seconds, false
    change_column_null :plugin_job_runs, :payload_digest_version, false
    change_column_default :plugin_job_runs,
      :payload_digest_version,
      from: nil,
      to: PAYLOAD_DIGEST_VERSION
    add_check_constraint :plugin_job_runs,
      "requested_wait_seconds BETWEEN 0 AND #{MAX_WAIT_SECONDS}",
      name: "plugin_job_runs_requested_wait_bounds"
    add_check_constraint :plugin_job_runs,
      "payload_digest_version = #{PAYLOAD_DIGEST_VERSION}",
      name: "plugin_job_runs_payload_digest_version"
  end

  def down
    remove_check_constraint :plugin_job_runs,
      name: "plugin_job_runs_payload_digest_version"
    remove_check_constraint :plugin_job_runs,
      name: "plugin_job_runs_requested_wait_bounds"
    MigrationPluginJobRun.reset_column_information

    MigrationPluginJobRun.find_each do |record|
      canonical = canonical_payload(record, record.requested_wait_seconds)
      legacy_digest = Digest::SHA256.hexdigest(canonical)
      record.update_column(:payload_digest, legacy_digest)
      unless record.reload.payload_digest == legacy_digest
        raise "plugin job payload digest rollback verification failed for row #{record.id}"
      end
    end

    remove_column :plugin_job_runs, :payload_digest_version, :integer
    remove_column :plugin_job_runs, :requested_wait_seconds, :integer
    MigrationPluginJobRun.reset_column_information
  end

  private

  def recover_wait_seconds!(record)
    approximate = record.scheduled_at - record.created_at
    candidates = [
      approximate.round,
      approximate.floor,
      approximate.ceil
    ].uniq.select { |value| value.between?(0, MAX_WAIT_SECONDS) }
    matched = candidates.find do |wait_seconds|
      Digest::SHA256.hexdigest(canonical_payload(record, wait_seconds)) ==
        record.payload_digest
    end
    return matched if matched

    raise "cannot verify legacy plugin job payload digest for row #{record.id}"
  end

  def canonical_payload(record, wait_seconds)
    JSON.generate(
      {
        "plugin_id" => record.owner_plugin_id,
        "plugin_version" => record.plugin_version,
        "job_key" => record.job_key,
        "contribution_schema_version" => record.contribution_schema_version,
        "declaration_digest" => record.declaration_digest,
        "arguments" => record.arguments.to_h.sort.to_h,
        "idempotency_key" => record.idempotency_key,
        "wait_seconds" => wait_seconds
      }
    )
  end

  def payload_digest_key
    Lockbox.attribute_key(
      table: "plugin_job_runs",
      attribute: "payload_digest",
      encode: false
    )
  end
end
