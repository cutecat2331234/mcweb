# frozen_string_literal: true

require "json"
require "pathname"
require "securerandom"
require "time"

module Mcweb
  module Plugins
    module Marketplace
      class OperationJournal
        MAX_MESSAGE_LENGTH = 2_048

        def initialize(path:, clock: -> { Time.now.utc })
          @path = Pathname(path)
          @clock = clock
        end

        def start(action:, plugin_id: nil)
          operation_id = SecureRandom.uuid
          append(
            operation_id: operation_id,
            action: action.to_s,
            status: "started",
            plugin_id: plugin_id,
            occurred_at: timestamp
          )
          operation_id
        end

        def finish(operation_id:, action:, status:, plugin_id: nil, version: nil, source: nil,
                   sha256: nil, message: nil, error_class: nil, recovery_path: nil)
          append(
            operation_id: operation_id,
            action: action.to_s,
            status: status.to_s,
            plugin_id: plugin_id,
            version: version,
            source: source,
            sha256: sha256,
            message: sanitize_message(message),
            error_class: error_class,
            recovery_path: recovery_path,
            occurred_at: timestamp
          )
        end

        def recent(limit: 100)
          return [].freeze unless @path.file?

          limit = Integer(limit)
          raise ArgumentError, "limit must be between 1 and 1,000" unless limit.between?(1, 1_000)

          lines = []
          File.foreach(@path, chomp: true) do |line|
            lines << line
            lines.shift if lines.length > limit
          end
          lines.filter_map do |line|
            JSON.parse(line).freeze
          rescue JSON::ParserError
            nil
          end.freeze
        rescue Errno::ENOENT
          [].freeze
        end

        private

        def append(attributes)
          payload = attributes.compact
          @path.dirname.mkpath(mode: 0o700)
          File.open(@path, File::WRONLY | File::APPEND | File::CREAT, 0o600) do |file|
            file.flock(File::LOCK_EX)
            file.write(JSON.generate(payload))
            file.write("\n")
            file.flush
            file.fsync
          ensure
            file.flock(File::LOCK_UN)
          end
          payload.freeze
        end

        def sanitize_message(message)
          return if message.nil?

          message.to_s.encode(
            Encoding::UTF_8,
            invalid: :replace,
            undef: :replace,
            replace: "?"
          ).gsub(/[[:cntrl:]]+/, " ").slice(0, MAX_MESSAGE_LENGTH)
        end

        def timestamp
          @clock.call.utc.iso8601(6)
        end
      end
    end
  end
end
