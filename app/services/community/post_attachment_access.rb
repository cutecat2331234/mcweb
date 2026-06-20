# frozen_string_literal: true

module Community
  module PostAttachmentAccess
    module_function

    def downloadable?(attachment, user:)
      return false unless attachment.file.attached?

      if attachment.linked?
        post = attachment.post
        return false unless post

        Community::PostAccess.readable?(post: post, user: user)
      else
        user&.id == attachment.user_id
      end
    end
  end
end
