# frozen_string_literal: true

module Minecraft
  module ConnectorOnlineRoster
    ROSTER_KEY = "connector_online_roster"
    ROSTER_TTL = 3.minutes

    module_function

    def normalize_uuid(value)
      value.to_s.strip.downcase.delete("-")
    end

    def record!(server:, uuids:, at: Time.current)
      normalized = Array(uuids).filter_map { |uuid| normalize_uuid(uuid) }.uniq
      return if normalized.empty?

      server.update!(
        metadata: server.metadata.merge(
          ROSTER_KEY => {
            "uuids" => normalized,
            "recorded_at" => at.iso8601
          }
        )
      )
    end

    def includes?(server:, uuid:)
      entry = server.metadata[ROSTER_KEY]
      return false unless entry.is_a?(Hash)

      recorded_at = Time.zone.parse(entry["recorded_at"].to_s)
      return false if recorded_at.nil? || recorded_at < ROSTER_TTL.ago

      Array(entry["uuids"]).map { |value| normalize_uuid(value) }.include?(normalize_uuid(uuid))
    end

    def validate_presence_roster!(server:, payload:)
      uuid = normalize_uuid(payload["uuid"])
      roster = Array(payload["online_player_uuids"]).map { |value| normalize_uuid(value) }

      return ServiceResult.failure(error: "Player is not listed as online on this server.") if uuid.blank?
      return ServiceResult.failure(error: "online_player_uuids is required.") if roster.empty?
      return ServiceResult.failure(error: "Player is not listed as online on this server.") unless roster.include?(uuid)

      record!(server: server, uuids: roster)
      ServiceResult.success
    end
  end
end
