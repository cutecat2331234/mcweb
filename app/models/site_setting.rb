class SiteSetting < ApplicationRecord
  CACHE_NAMESPACE = "site-settings/v1"

  validates :key, presence: true, uniqueness: true
  after_commit :expire_cached_value

  def self.get(key, default = nil)
    cached = Rails.cache.fetch(cache_key(key)) do
      setting = find_by(key: key)
      {
        "found" => setting.present?,
        "value" => setting&.value
      }
    end
    cached.fetch("found") ? cached["value"] : default
  end

  def self.set(key, value)
    setting = find_or_initialize_by(key: key)
    setting.value = value
    setting.save!
    value
  rescue ActiveRecord::RecordNotUnique
    find_by!(key: key).update!(value: value)
    value
  end

  def self.unset(key)
    deleted = where(key: key).delete_all
    Rails.cache.delete(cache_key(key))
    Website::HomeCache.bump! if key.to_s.start_with?("features.", "store.features.")
    deleted
  end

  def self.fetch(key, default = nil, &block)
    cached = Rails.cache.fetch(cache_key(key)) do
      setting = find_by(key: key)
      {
        "found" => setting.present?,
        "value" => setting&.value
      }
    end
    return cached["value"] if cached.fetch("found")

    value = block ? yield : default
    set(key, value) unless value.nil?
    value
  end

  def self.cache_key(key)
    [ CACHE_NAMESPACE, key.to_s ]
  end

  private

  def expire_cached_value
    Rails.cache.delete(self.class.cache_key(key))
    Website::HomeCache.bump! if key.to_s.start_with?("features.", "store.features.")
    if saved_change_to_key?
      Rails.cache.delete(self.class.cache_key(key_before_last_save))
      Website::HomeCache.bump! if key_before_last_save.to_s.start_with?(
        "features.",
        "store.features."
      )
    end
  end
end
