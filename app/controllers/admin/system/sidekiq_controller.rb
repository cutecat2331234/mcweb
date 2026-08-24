# frozen_string_literal: true

module Admin
  module System
    class SidekiqController < BaseController
      SAFE_QUERY_KEYS = %w[
        count days direction only page period poll substr
      ].freeze
      METRICS_PERIODS = %w[1h 2h 4h 8h 24h 48h 72h].freeze
      METRICS_DETAIL_PERIODS = %w[1h 2h 4h 8h].freeze
      MAX_PATH_BYTES = 2_048
      MAX_PATH_SEGMENT_BYTES = 512
      MAX_QUERY_VALUE_BYTES = 512
      MAX_PAGE = 10_000
      MAX_PAGE_SIZE = 100
      INVALID_PATH_SEGMENT = /[\\\u0000-\u001F\u007F]/

      before_action -> { require_permission("system.sidekiq.read") }

      def index
        frame_url = sidekiq_url
        return head :not_found unless frame_url

        render inertia: "Admin/System/Sidekiq/Index", props: {
          sidekiqUrl: frame_url
        }
      end

      private

      def sidekiq_url
        path = sidekiq_path
        return unless path

        query = safe_sidekiq_query(path).to_query
        return path if query.blank?

        "#{path}?#{query}"
      end

      def sidekiq_path
        raw_path = params[:sidekiq_path].to_s
        return "/jobs/" if raw_path.blank?
        return if raw_path.bytesize > MAX_PATH_BYTES

        segments = raw_path.split("/", -1)
        return unless segments.all? { |segment| valid_path_segment?(segment) }
        return unless valid_page_shape?(segments)

        encoded_path = segments
          .map { |segment| ERB::Util.url_encode(segment).gsub("+", "%20") }
          .join("/")
        return if encoded_path.bytesize > MAX_PATH_BYTES

        "/jobs/#{encoded_path}"
      end

      def valid_path_segment?(segment)
        segment.present? &&
          segment.bytesize <= MAX_PATH_SEGMENT_BYTES &&
          segment != "." &&
          segment != ".." &&
          !segment.match?(INVALID_PATH_SEGMENT)
      end

      def valid_page_shape?(segments)
        case segments.first
        when "busy"
          segments.length == 1
        when "queues", "morgue", "retries", "scheduled", "metrics"
          segments.length.in?([ 1, 2 ])
        when "profiles"
          segments.length == 1
        when "cron"
          valid_cron_page_shape?(segments)
        else
          false
        end
      end

      def valid_cron_page_shape?(segments)
        segments.length == 1 ||
          (segments.length == 3 && segments[1] == "namespaces") ||
          (
            segments.length == 5 &&
              segments[1] == "namespaces" &&
              segments[3] == "jobs"
          )
      end

      def safe_sidekiq_query(path)
        request.query_parameters.each_with_object({}) do |(key, value), safe|
          next unless SAFE_QUERY_KEYS.include?(key.to_s)
          next unless value.is_a?(String)
          next unless query_key_allowed_for_path?(key.to_s, path)

          normalized_value = normalize_query_value(key.to_s, value, path)
          next unless normalized_value

          safe[key.to_s] = normalized_value
        end
      end

      def query_key_allowed_for_path?(key, path)
        segments = path.delete_prefix("/jobs/").split("/").reject(&:blank?)
        root = segments.first

        case key
        when "days"
          segments.empty?
        when "period"
          root == "metrics"
        when "only"
          segments == [ "busy" ]
        when "direction"
          root == "queues" && segments.length == 2
        when "substr"
          %w[metrics retries scheduled morgue].include?(root) &&
            segments.length == 1
        when "count", "page"
          segments == [ "busy" ] ||
            (root == "queues" && segments.length == 2) ||
            (%w[retries scheduled morgue].include?(root) && segments.length == 1)
        when "poll"
          segments.any? && root != "metrics"
        else
          false
        end
      end

      def normalize_query_value(key, value, path)
        return if value.bytesize > MAX_QUERY_VALUE_BYTES

        case key
        when "count"
          bounded_integer(value, 1..MAX_PAGE_SIZE)
        when "days"
          bounded_integer(value, 1..180)
        when "page"
          bounded_integer(value, 1..MAX_PAGE)
        when "direction"
          value if %w[asc desc].include?(value)
        when "only"
          value if %w[jobs processes].include?(value)
        when "period"
          normalize_metrics_period(value, path)
        when "poll"
          value if value == "true"
        when "substr"
          value
        end
      end

      def normalize_metrics_period(value, path)
        return unless METRICS_PERIODS.include?(value)
        return value unless path.start_with?("/jobs/metrics/")

        METRICS_DETAIL_PERIODS.include?(value) ? value : "8h"
      end

      def bounded_integer(value, range)
        return unless value.match?(/\A\d+\z/)

        integer = value.to_i
        integer.to_s if range.cover?(integer)
      end
    end
  end
end
