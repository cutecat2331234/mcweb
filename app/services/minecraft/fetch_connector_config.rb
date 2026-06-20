# frozen_string_literal: true

module Minecraft
  class FetchConnectorConfig < ApplicationService
    def initialize(server:)
      @server = server
    end

    def call
      link_command = SiteSetting.get("minecraft.link_command", "/website link").to_s.strip
      parts = link_command.split(/\s+/)
      command_root = parts.first.to_s.delete_prefix("/")
      link_subcommand = parts[1].presence || "link"

      ServiceResult.success(
        server_id: @server.public_id,
        link_command: link_command,
        command_root: command_root,
        link_subcommand: link_subcommand,
        messages: {
          link_success: SiteSetting.get("minecraft.link_success_message", I18n.t("mcweb.minecraft.connector.link_success")),
          link_code: SiteSetting.get("minecraft.link_code_message", I18n.t("mcweb.minecraft.connector.link_code")),
          link_failed: SiteSetting.get("minecraft.link_failed_message", I18n.t("mcweb.minecraft.connector.link_failed")),
          whois_failed: SiteSetting.get("minecraft.whois_failed_message", I18n.t("mcweb.minecraft.whois.lookup_failed"))
        },
        skin_mode: SiteSetting.get("minecraft.profile.skin_mode", "2d"),
        bridges: SiteSetting.get("minecraft.bridges.enabled", "placeholderapi,luckperms,vault").to_s.split(",").map(&:strip),
        bridge_placeholders: SiteSetting.get("minecraft.bridges.placeholders", "").to_s.split(",").map(&:strip).reject(&:blank?),
        task_handlers: {
          "broadcast_announcement" => { "description" => I18n.t("mcweb.minecraft.tasks.broadcast_announcement") },
          "run_commands" => { "description" => I18n.t("mcweb.minecraft.tasks.run_commands") },
          "deliver_item" => { "description" => I18n.t("mcweb.minecraft.tasks.deliver_item") }
        },
        profile_sections: SiteSetting.get("minecraft.profile.sections", "minecraft,trust,memberships,roles,game_groups").to_s.split(",").map(&:strip)
      )
    end
  end
end
