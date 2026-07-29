# frozen_string_literal: true

require "aws-sdk-s3"
require "json"
require "redis"
require "stringio"

module ProductionAcceptanceProbe
  DATABASE_PREFIX = "mcweb_acceptance_"
  MARKER_KEY = "acceptance.release.marker"
  MARKER_VALUE = "preserved-through-upgrade-and-restore"
  OBJECT_CONTENT = "mcweb production acceptance object\n"

  module_function

  def run!
    database = ActiveRecord::Base.connection_db_config.database.to_s
    unless Rails.env.production? && database.start_with?(DATABASE_PREFIX)
      abort(
        "Refusing production acceptance probe outside a protected database; " \
        "environment=#{Rails.env} database=#{database.inspect}"
      )
    end

    case ENV.fetch("MCWEB_ACCEPTANCE_ACTION")
    when "seed-fresh"
      ensure_bucket!
      ensure_owner!
      SiteSetting.set(MARKER_KEY, MARKER_VALUE)
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(OBJECT_CONTENT),
        filename: "production-acceptance.txt",
        content_type: "text/plain",
        service_name: "private_s3",
        identify: false
      )
      abort("object upload did not reach S3") unless blob.service.exist?(blob.key)
      redis_round_trip!
      report(database:, blob_key: blob.key, phase: "fresh")
    when "verify-fresh"
      verify_current_schema!
      verify_marker!
      verify_object!
      redis_round_trip!
      report(database:, phase: "fresh-verified")
    when "seed-upgrade"
      ensure_owner!
      SiteSetting.set(MARKER_KEY, MARKER_VALUE)
      report(database:, phase: "upgrade-seeded")
    when "verify-upgrade"
      verify_current_schema!
      verify_marker!
      redis_round_trip!
      report(database:, phase: "upgrade-verified")
    when "verify-restored"
      verify_current_schema!
      verify_marker!
      verify_object!
      redis_round_trip!
      report(database:, phase: "restore-verified")
    else
      abort("Unsupported MCWEB_ACCEPTANCE_ACTION")
    end
  end

  def ensure_bucket!
    client.create_bucket(bucket: bucket)
  rescue Aws::S3::Errors::BucketAlreadyOwnedByYou, Aws::S3::Errors::BucketAlreadyExists
    nil
  end

  def ensure_owner!
    owner = User.find_or_initialize_by(email: "production-acceptance@mcweb.internal")
    owner.assign_attributes(
      username: "acceptance_owner",
      password: "Acceptance-password-123!",
      password_confirmation: "Acceptance-password-123!",
      email_verified: true,
      email_verified_at: Time.current,
      locale: "en",
      time_zone: "UTC",
      status: "active",
      account_type: "owner",
      totp_enabled: false
    )
    owner.save!
    InstallationLock.lock!(user: owner)
  end

  def verify_current_schema!
    expected = Dir[Rails.root.join("db/migrate/*.rb")]
      .filter_map { |path| File.basename(path)[/\A(\d+)_/, 1] }
      .max
    actual = ActiveRecord::Base.connection_pool.schema_migration.versions.max
    abort("schema is not current: expected=#{expected} actual=#{actual}") unless actual == expected
  end

  def verify_marker!
    actual = SiteSetting.get(MARKER_KEY)
    abort("release marker was not preserved") unless actual == MARKER_VALUE
  end

  def verify_object!
    blob = ActiveStorage::Blob.find_by(filename: "production-acceptance.txt")
    abort("restored object metadata is missing") unless blob
    abort("restored object is absent from S3") unless blob.service.exist?(blob.key)
    abort("restored object content differs") unless blob.download == OBJECT_CONTENT
  end

  def redis_round_trip!
    key = "mcweb:acceptance:#{Process.pid}"
    connection = Redis.new(url: ENV.fetch("REDIS_URL"), connect_timeout: 2, read_timeout: 2)
    connection.set(key, "ok", ex: 30)
    abort("Redis round trip failed") unless connection.get(key) == "ok"
  ensure
    connection&.del(key)
    connection&.close
  end

  def client
    @client ||= Aws::S3::Client.new(
      endpoint: ENV.fetch("MCWEB_S3_ENDPOINT"),
      region: ENV.fetch("MCWEB_S3_REGION"),
      access_key_id: ENV.fetch("MCWEB_S3_ACCESS_KEY_ID"),
      secret_access_key: ENV.fetch("MCWEB_S3_SECRET_ACCESS_KEY"),
      force_path_style: true
    )
  end

  def bucket
    ENV.fetch("MCWEB_S3_BUCKET")
  end

  def report(payload)
    puts JSON.generate(payload)
  end
end

ProductionAcceptanceProbe.run!
