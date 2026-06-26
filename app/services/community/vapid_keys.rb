# frozen_string_literal: true

module Community
  # VAPID keypair for Web Push, generated once and stored in SiteSetting.
  module VapidKeys
    PUBLIC_SETTING = "forum.vapid_public_key"
    PRIVATE_SETTING = "forum.vapid_private_key"

    module_function

    def public_key
      ensure_keys[:public]
    end

    def private_key
      ensure_keys[:private]
    end

    def ensure_keys
      pub = SiteSetting.get(PUBLIC_SETTING)
      priv = SiteSetting.get(PRIVATE_SETTING)
      return { public: pub, private: priv } if pub.present? && priv.present?

      key = WebPush.generate_key
      SiteSetting.set(PUBLIC_SETTING, key.public_key)
      SiteSetting.set(PRIVATE_SETTING, key.private_key)
      { public: key.public_key, private: key.private_key }
    end
  end
end
