# frozen_string_literal: true

require "bigdecimal"
require "test_helper"
require "mcweb/plugins/job_contribution"
require "tmpdir"

class Mcweb::Plugins::JobContributionTest < ActiveSupport::TestCase
  setup do
    @root = Pathname(Dir.mktmpdir("mcweb-job-contribution"))
  end

  teardown do
    FileUtils.remove_entry(@root) if @root&.exist?
  end

  test "loader accepts a strict immutable jobs contribution" do
    manifest = write_plugin(valid_document)
    contribution = Mcweb::Plugins::JobContributionLoader.load(manifest)
    job = contribution.fetch("deliver")

    assert_equal "acme/jobs", contribution.plugin_id
    assert_equal "1", contribution.version
    assert_match(/\A[0-9a-f]{64}\z/, contribution.digest)
    assert_equal "acme/jobs:deliver", job.qualified_key
    assert_equal 3, job.max_attempts
    assert_equal [ "message", "recipient_id" ], job.required_keys
    assert_predicate contribution, :frozen?
    assert_predicate contribution.jobs, :frozen?
    assert_predicate job, :frozen?
    assert_predicate contribution.to_h, :frozen?
  end

  test "argument validation is closed and deeply frozen" do
    declaration = Mcweb::Plugins::JobContribution.new(
      plugin_id: "acme/jobs",
      document: valid_document
    ).fetch("deliver")
    arguments = declaration.validate_arguments(
      recipient_id: SecureRandom.uuid,
      message: "hello",
      urgent: true
    )

    assert_predicate arguments, :frozen?
    assert_predicate arguments.keys.first, :frozen?
    assert_raises(FrozenError) { arguments["message"] = "changed" }

    failures = [
      { recipient_id: SecureRandom.uuid, message: "hello", unknown: true },
      { recipient_id: "not-a-uuid", message: "hello" },
      { recipient_id: SecureRandom.uuid, message: Object.new },
      { recipient_id: SecureRandom.uuid }
    ]
    failures.each do |candidate|
      error = assert_raises(Mcweb::Plugins::JobValidationError) do
        declaration.validate_arguments(candidate)
      end
      assert_equal "validation_failed", error.code
      refute_includes error.message, candidate.to_s
    end
  end

  test "schema rejects arbitrary handlers open objects and unknown keywords" do
    invalid_documents = [
      valid_document.deep_merge("jobs" => { "deliver" => { "handler" => "Kernel" } }),
      valid_document.deep_merge(
        "jobs" => {
          "deliver" => {
            "arguments" => { "additionalProperties" => true }
          }
        }
      ),
      valid_document.deep_merge(
        "jobs" => {
          "deliver" => {
            "arguments" => {
              "properties" => {
                "message" => { "type" => "object" }
              }
            }
          }
        }
      ),
      valid_document.merge("unknown" => true)
    ]

    invalid_documents.each do |document|
      assert_raises(Mcweb::Plugins::ManifestError) do
        Mcweb::Plugins::JobContribution.new(
          plugin_id: "acme/jobs",
          document:
        )
      end
    end
  end

  test "number arguments accept only native JSON numeric scalars" do
    document = valid_document.deep_dup
    properties = document
      .fetch("jobs")
      .fetch("deliver")
      .fetch("arguments")
      .fetch("properties")
    properties["score"] = { "type" => "number" }
    declaration = Mcweb::Plugins::JobContribution.new(
      plugin_id: "acme/jobs",
      document:
    ).fetch("deliver")
    base = {
      recipient_id: SecureRandom.uuid,
      message: "hello"
    }

    assert_equal 5, declaration.validate_arguments(base.merge(score: 5)).fetch("score")
    assert_equal 1.25,
      declaration.validate_arguments(base.merge(score: 1.25)).fetch("score")
    [ BigDecimal("1.25"), Rational(5, 4) ].each do |unsupported|
      error = assert_raises(Mcweb::Plugins::JobValidationError) do
        declaration.validate_arguments(base.merge(score: unsupported))
      end
      assert_equal "validation_failed", error.code
    end
  end

  test "loader rejects duplicate keys and paths outside the plugin package" do
    manifest = write_plugin(valid_document)
    jobs_path = Pathname(manifest.source_path).dirname.join("config/jobs.yml")
    File.write(
      jobs_path,
      <<~YAML
        schema_version: "1"
        schema_version: "2"
        jobs: {}
      YAML
    )
    assert_raises(Mcweb::Plugins::ManifestError) do
      Mcweb::Plugins::JobContributionLoader.load(manifest)
    end

    outside = @root.join("outside.yml")
    File.write(outside, YAML.dump(valid_document))
    assert_raises(Mcweb::Plugins::ManifestError) do
      Mcweb::Plugins::Manifest.from_hash(
        {
          id: "acme/jobs",
          name: "Jobs",
          version: "1.0.0",
          api_version: "1",
          contributions: { jobs: "../outside.yml" }
        },
        source_path: @root.join("plugin/mcweb_plugin.yml").to_s
      )
    end
  end

  private

  def valid_document
    {
      "schema_version" => "1",
      "jobs" => {
        "deliver" => {
          "max_attempts" => 3,
          "retry_wait_seconds" => 5,
          "lease_seconds" => 60,
          "arguments" => {
            "$schema" => Mcweb::Plugins::JobContribution::DRAFT_URI,
            "type" => "object",
            "additionalProperties" => false,
            "required" => %w[recipient_id message],
            "properties" => {
              "recipient_id" => {
                "type" => "string",
                "format" => "uuid"
              },
              "message" => {
                "type" => "string",
                "minLength" => 1,
                "maxLength" => 1_024
              },
              "urgent" => {
                "type" => "boolean"
              }
            }
          }
        }
      }
    }
  end

  def write_plugin(document)
    directory = @root.join("plugin")
    FileUtils.mkdir_p(directory.join("config"))
    File.write(directory.join("config/jobs.yml"), YAML.dump(document))
    File.write(
      directory.join("mcweb_plugin.yml"),
      YAML.dump(
        "id" => "acme/jobs",
        "name" => "Jobs",
        "version" => "1.0.0",
        "api_version" => "1",
        "contributions" => { "jobs" => "config/jobs.yml" }
      )
    )
    Mcweb::Plugins::Manifest.load_file(directory.join("mcweb_plugin.yml"))
  end
end
