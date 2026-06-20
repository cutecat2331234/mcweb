# frozen_string_literal: true

module ServiceErrorTranslator
  EXACT = {
    "Invalid or expired verification token." => "mcweb.services.errors.invalid_or_expired_verification_token",
    "Invalid or expired reset token." => "mcweb.services.errors.invalid_or_expired_reset_token",
    "Recipient not found." => "mcweb.services.errors.recipient_not_found",
    "You cannot message yourself." => "mcweb.services.errors.cannot_message_self",
    "You cannot message this user." => "mcweb.services.errors.cannot_message_user",
    "New members cannot send private messages yet." => "mcweb.services.errors.new_members_cannot_send_pm",
    "New members cannot post links. Participate more to unlock this." => "mcweb.services.errors.new_members_cannot_post_links",
    "Message is too short." => "mcweb.services.errors.message_too_short",
    "Not a participant." => "mcweb.services.errors.not_a_participant",
    "Invalid parent post." => "mcweb.services.errors.invalid_parent_post",
    "Slow mode is active. Please wait before posting again." => "mcweb.services.errors.slow_mode_active",
    "Please wait before posting again." => "mcweb.services.errors.wait_before_posting",
    "Invalid or expired link code." => "mcweb.services.errors.invalid_or_expired_link_code",
    "Invalid connector signature." => "mcweb.services.errors.invalid_connector_signature",
    "Server connector is not configured." => "mcweb.services.errors.server_connector_not_configured",
    "Invalid URL." => "mcweb.services.errors.invalid_url",
    "Invalid reaction." => "mcweb.services.errors.invalid_reaction",
    "Content not found." => "mcweb.services.errors.content_not_found",
    "Invalid email or password." => "mcweb.services.errors.invalid_email_or_password",
    "Group title is required." => "mcweb.services.errors.group_title_required",
    "Add at least one other participant." => "mcweb.services.errors.add_other_participant",
    "Too many participants." => "mcweb.services.errors.too_many_participants",
    "You are not allowed to share this topic." => "mcweb.services.errors.cannot_share_topic",
    "Not a group conversation." => "mcweb.services.errors.not_group_conversation",
    "User not found." => "mcweb.services.errors.user_not_found",
    "User is not a participant." => "mcweb.services.errors.user_not_participant",
    "Not allowed." => "mcweb.services.errors.not_allowed",
    "Cannot remove the last participant." => "mcweb.services.errors.cannot_remove_last_participant",
    "Only participants can add members." => "mcweb.services.errors.only_participants_can_add",
    "Group is full." => "mcweb.services.errors.group_full",
    "Only the group creator can add members." => "mcweb.services.errors.only_creator_can_add",
    "User is already a participant." => "mcweb.services.errors.user_already_participant",
    "Cannot add yourself." => "mcweb.services.errors.cannot_add_self",
    "Cannot message blocked user." => "mcweb.services.errors.cannot_message_blocked_user",
    "User is silenced." => "mcweb.services.errors.user_silenced",
    "User cannot participate in private messages." => "mcweb.services.errors.user_cannot_pm",
    "Your cart is empty." => "mcweb.services.errors.cart_empty",
    "Order created." => "mcweb.services.errors.order_created",
    "Report submitted." => "mcweb.services.errors.report_submitted",
    "Reset token has expired." => "mcweb.services.errors.reset_token_expired",
    "Email or token with new password is required." => "mcweb.services.errors.email_or_token_required",
    "You are not allowed to vote in this topic." => "mcweb.services.errors.cannot_vote_in_topic",
    "Poll is closed." => "mcweb.services.errors.poll_closed",
    "No options selected." => "mcweb.services.errors.no_options_selected",
    "Too many options selected." => "mcweb.services.errors.too_many_options_selected",
    "Invalid option." => "mcweb.services.errors.invalid_poll_option",
    "Order cannot be cancelled." => "mcweb.services.errors.order_cannot_cancel",
    "Payment is not refundable." => "mcweb.services.errors.payment_not_refundable",
    "Refund amount exceeds remaining balance." => "mcweb.services.errors.refund_exceeds_balance",
    "Payment record not found." => "mcweb.services.errors.payment_not_found",
    "Payment is no longer valid." => "mcweb.services.errors.payment_invalid",
    "Order is not payable." => "mcweb.services.errors.order_not_payable",
    "Order has no shippable items." => "mcweb.services.errors.order_no_shippable_items",
    "You are not authorized to moderate this post." => "mcweb.services.errors.not_authorized_moderate_post",
    "Unknown moderation action." => "mcweb.services.errors.unknown_moderation_action",
    "Small action body is required." => "mcweb.services.errors.small_action_body_required",
    "Link code has already been used." => "mcweb.services.errors.link_code_used",
    "This Minecraft account is already linked." => "mcweb.services.errors.minecraft_already_linked",
    "Request timestamp is too old or invalid." => "mcweb.services.errors.request_timestamp_invalid",
    "You are not allowed to create topics in this section." => "mcweb.services.errors.cannot_create_topic_in_section",
    "Your trust level is too low to create topics in this section." => "mcweb.services.errors.trust_level_too_low",
    "This section is read-only." => "mcweb.services.errors.section_read_only",
    "Title is required." => "mcweb.services.errors.title_required",
    "Post body is too short." => "mcweb.services.errors.post_body_too_short",
    "You are muted in this section." => "mcweb.services.errors.muted_in_section",
    "Your account is banned." => "mcweb.services.errors.account_banned",
    "You are silenced and cannot post." => "mcweb.services.errors.silenced_cannot_post",
    "You are banned from replying in this topic." => "mcweb.services.errors.topic_reply_banned",
    "Please wait before creating another topic." => "mcweb.services.errors.wait_before_new_topic",
    "A similar topic was recently created." => "mcweb.services.errors.similar_topic_recent"
  }.freeze

  PATTERNS = [
    [ /\AYou cannot message (.+)\.\z/, "mcweb.services.errors.cannot_message_user_named", :name ],
    [ /\ACannot message blocked user (.+)\.\z/, "mcweb.services.errors.cannot_message_blocked_named", :name ],
    [ /\AUsers not found: (.+)\z/, "mcweb.services.errors.users_not_found", :names ]
  ].freeze

  module_function

  def translate(message)
    text = message.to_s.strip
    return text if text.blank?

    if (key = EXACT[text])
      return I18n.t(key, default: text)
    end

    PATTERNS.each do |pattern, key, param|
      match = text.match(pattern)
      return I18n.t(key, param => match[1], default: text) if match
    end

    if text.match?(/\A[a-z][a-z0-9_]*\z/) && I18n.exists?("mcweb.services.errors.#{text}", locale: I18n.locale)
      return I18n.t("mcweb.services.errors.#{text}")
    end

    text
  end
end
