# frozen_string_literal: true

module Community
  module NotificationDestinationUrl
    module_function

    def for(notification, root_url:)
      path = notification.destination_path
      return nil if path.blank?

      return path if path.match?(%r{\Ahttps?://}i)

      "#{root_url.to_s.chomp('/')}#{path}"
    end
  end
end
