# frozen_string_literal: true

require "digest"
require "json"
require "pathname"
require "time"

module Operations
  class DeveloperCaptureStore
    DIRECTORIES = {
      "mail" => "tmp/developer-mode/mails",
      "webhooks" => "tmp/developer-mode/webhooks",
      "web_push" => "tmp/developer-mode/web-push"
    }.freeze
    MAX_FILES = 2_000
    MAX_PAGE = 100
    MAX_PER_PAGE = 50
    MAX_BROWSE_BYTES = 8.megabytes
    MAX_LINE_BYTES = 32.kilobytes
    UUID_PATTERN =
      /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i
    HTTP_METHODS = %w[DELETE GET HEAD OPTIONS PATCH POST PUT].freeze
    SAFE_TOKEN_PATTERN = /\A[a-z0-9_.:-]{1,64}\z/i

    def initialize(root: Rails.root)
      @root = Pathname(root).expand_path
    end

    def page(kind:, page: 1, per_page: 20)
      normalized_kind = normalize_kind!(kind)
      page = page.to_i.clamp(1, MAX_PAGE)
      per_page = per_page.to_i.clamp(1, MAX_PER_PAGE)
      offset = (page - 1) * per_page
      entries = browse_entries(normalized_kind, limit: offset + per_page + 1)
      visible = entries.slice(offset, per_page) || []

      {
        kind: normalized_kind,
        page: page,
        perPage: per_page,
        hasPreviousPage: page > 1,
        hasNextPage: entries.length > offset + per_page,
        entries: visible
      }
    end

    def clear!(kind:)
      kinds =
        kind.to_s == "all" ? DIRECTORIES.keys : [ normalize_kind!(kind) ]
      deleted_files = 0
      deleted_bytes = 0

      kinds.each do |capture_kind|
        directory = safe_directory(capture_kind)
        next unless directory

        capture_files(directory).each do |path|
          deleted_bytes += safe_file_size(path)
          File.delete(path)
          deleted_files += 1
        rescue Errno::EACCES, Errno::ENOENT, SystemCallError
          next
        end
      end

      {
        kinds: kinds,
        deletedFiles: deleted_files,
        deletedBytes: deleted_bytes
      }
    end

    private

    def normalize_kind!(kind)
      normalized = kind.to_s.tr("-", "_")
      return normalized if DIRECTORIES.key?(normalized)

      raise ArgumentError, "unsupported capture kind"
    end

    def browse_entries(kind, limit:)
      directory = safe_directory(kind)
      return [] unless directory

      files = capture_files(directory)
      entries =
        if kind == "mail"
          files.first(limit).map { |path| mail_entry(path) }
        else
          jsonl_entries(files, kind, limit:)
        end

      entries
        .compact
        .sort_by { |entry| entry.fetch(:capturedAt, "") }
        .reverse
        .first(limit)
    end

    def safe_directory(kind)
      directory = @root.join(DIRECTORIES.fetch(kind))
      return unless directory.directory?

      root = @root.realpath
      resolved = directory.realpath
      return unless inside?(resolved, root)

      resolved
    rescue Errno::EACCES, Errno::ENOENT, SystemCallError
      nil
    end

    def capture_files(directory)
      directory.each_child
        .first(MAX_FILES)
        .filter_map do |path|
          next if path.symlink? || !path.file?

          resolved = path.realpath
          resolved if inside?(resolved, directory)
        rescue Errno::EACCES, Errno::ENOENT, SystemCallError
          nil
        end
        .sort_by { |path| safe_file_mtime(path) }
        .reverse
    end

    def mail_entry(path)
      {
        captureRef: Digest::SHA256.hexdigest(path.basename.to_s).first(8),
        capturedAt: safe_file_mtime(path).utc.iso8601(6),
        sizeBytes: safe_file_size(path),
        kind: "mail"
      }
    end

    def jsonl_entries(files, kind, limit:)
      entries = []
      remaining_bytes = MAX_BROWSE_BYTES

      files.each do |path|
        break if entries.length >= limit || remaining_bytes <= 0

        size = safe_file_size(path)
        length = [ size, remaining_bytes ].min
        remaining_bytes -= length
        tail_lines(path, length: length, size: size).reverse_each do |line|
          next if line.bytesize > MAX_LINE_BYTES

          parsed = JSON.parse(line)
          entry = sanitize_jsonl_entry(parsed, kind)
          entries << entry if entry
          break if entries.length >= limit
        rescue JSON::ParserError, TypeError
          next
        end
      end

      entries
    end

    def tail_lines(path, length:, size:)
      return [] if size.zero? || length.zero?

      File.open(path, "rb") do |file|
        file.seek(size - length, IO::SEEK_SET)
        lines = file.read(length).to_s.lines
        lines.shift if length < size
        lines
      end
    rescue Errno::EACCES, Errno::ENOENT, IOError, SystemCallError
      []
    end

    def sanitize_jsonl_entry(entry, kind)
      return unless entry.is_a?(Hash)

      capture_id = entry["id"].to_s
      captured_at = safe_iso8601(entry["captured_at"])
      return unless capture_id.match?(UUID_PATTERN) && captured_at

      base = {
        captureRef: capture_id.first(8).downcase,
        capturedAt: captured_at,
        kind: kind
      }
      if kind == "webhooks"
        method = entry["method"].to_s.upcase
        base[:method] = HTTP_METHODS.include?(method) ? method : "OTHER"
      else
        notification_type = entry.dig("notification", "type").to_s
        base[:notificationType] =
          notification_type.match?(SAFE_TOKEN_PATTERN) ?
            notification_type :
            "other"
      end
      base
    end

    def safe_iso8601(value)
      Time.iso8601(value.to_s).utc.iso8601(6)
    rescue ArgumentError
      nil
    end

    def inside?(path, directory)
      value = path.to_s
      base = directory.to_s
      value == base || value.start_with?("#{base}#{File::SEPARATOR}")
    end

    def safe_file_size(path)
      path.size
    rescue Errno::EACCES, Errno::ENOENT, SystemCallError
      0
    end

    def safe_file_mtime(path)
      path.mtime
    rescue Errno::EACCES, Errno::ENOENT, SystemCallError
      Time.at(0)
    end
  end
end
