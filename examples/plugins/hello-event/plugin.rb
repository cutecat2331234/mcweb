# frozen_string_literal: true

Mcweb::Plugins.register do |plugin|
  plugin.on("forum.topic.created") do |event|
    enabled = plugin.api.settings.get("enabled", default: true)
    next unless enabled.success? && enabled.value

    plugin.api.events.publish(
      "examples.hello_event.topic_seen",
      "source_event_id" => event.event_id,
      "topic_public_id" => event.data.dig("topic", "public_id") || event.data["topic_public_id"]
    )
  end
end
