# frozen_string_literal: true

class ForumRepliesMailbox < ApplicationMailbox
  def process
    result = Community::ProcessForumEmailReply.call(
      inbound_email: inbound_email,
      mail: mail,
      reply_tokens: Community::ForumEmailReplyAddress.reply_tokens_from(mail)
    )

    bounced! if result.failure?
  end
end
