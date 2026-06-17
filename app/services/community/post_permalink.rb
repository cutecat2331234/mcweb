# frozen_string_literal: true

module Community
  module PostPermalink
    module_function

    def path(topic, post)
      "/forum/topics/#{topic.public_id}#p-#{post.floor_number}"
    end

    def legacy_path(topic, post)
      "/forum/topics/#{topic.public_id}#post-#{post.id}"
    end
  end
end
