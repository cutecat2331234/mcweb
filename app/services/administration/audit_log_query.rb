# frozen_string_literal: true

module Administration
  class AuditLogQuery
    DEFAULT_PER_PAGE = 50
    MAX_PER_PAGE = 100
    MAX_EXPORT_ROWS = 10_000

    attr_reader :filters, :page, :per_page, :errors

    def initialize(filters:, scope: AuditLog.all, page: nil, per_page: nil)
      @scope = scope
      @filters = normalize_filters(filters)
      @page = positive_integer(page, fallback: 1)
      @per_page = positive_integer(per_page, fallback: DEFAULT_PER_PAGE).clamp(1, MAX_PER_PAGE)
      @errors = {}
    end

    def relation
      @relation ||= begin
        result = @scope
        result = filter_action(result)
        result = filter_actor(result)
        result = filter_resource(result)
        result = result.where(request_id: filters[:request_id]) if filters[:request_id].present?
        result = filter_time_range(result)
        result.recent
      end
    end

    def records
      relation.offset((page - 1) * per_page).limit(per_page)
    end

    def total
      @total ||= relation.count
    end

    def total_pages
      [ (total.to_f / per_page).ceil, 1 ].max
    end

    private

    def normalize_filters(raw)
      source = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
      %i[action actor resource_type resource request_id from to].index_with do |key|
        (source[key] || source[key.to_s]).to_s.strip.first(255).presence
      end
    end

    def positive_integer(value, fallback:)
      parsed = Integer(value, exception: false)
      parsed&.positive? ? parsed : fallback
    end

    def filter_action(relation)
      return relation if filters[:action].blank?

      pattern = "#{ActiveRecord::Base.sanitize_sql_like(filters[:action])}%"
      relation.where("audit_logs.action ILIKE ?", pattern)
    end

    def filter_actor(relation)
      return relation if filters[:actor].blank?

      actor = filters[:actor]
      actor_id = Integer(actor, exception: false)
      return relation.where(actor_id:) if actor_id&.positive?

      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(actor)}%"
      relation
        .left_joins(:actor)
        .where(
          "users.username ILIKE :pattern OR users.email ILIKE :pattern OR users.public_id = :actor",
          pattern:,
          actor:
        )
    end

    def filter_resource(relation)
      result = relation
      result = result.where(resource_type: filters[:resource_type]) if filters[:resource_type].present?
      return result if filters[:resource].blank?

      resource = filters[:resource]
      resource_id = Integer(resource, exception: false)
      if resource_id&.positive?
        result.where(resource_id:)
      else
        result.where(resource_public_id: resource)
      end
    end

    def filter_time_range(relation)
      result = relation
      if filters[:from].present?
        from = parse_time(filters[:from], boundary: :start)
        from ? result = result.where(created_at: from..) : errors[:from] = "invalid"
      end
      if filters[:to].present?
        to = parse_time(filters[:to], boundary: :end)
        to ? result = result.where(created_at: ..to) : errors[:to] = "invalid"
      end
      result
    end

    def parse_time(value, boundary:)
      parsed = Time.zone.parse(value)
      return unless parsed

      date_only = value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
      return parsed.beginning_of_day if date_only && boundary == :start
      return parsed.end_of_day if date_only && boundary == :end

      parsed
    rescue ArgumentError, TypeError
      nil
    end
  end
end
