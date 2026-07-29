# frozen_string_literal: true

Mcweb::Plugins.register do |plugin|
  plugin.on("forum.report.created") do |event|
    report = event.data["report"] || {}
    plugin.api.events.publish(
      "examples.forum_extension.review_requested",
      "source_event_id" => event.event_id,
      "report_public_id" => report["public_id"] || event.data["report_public_id"]
    )
  end
end
