class SiteSetting < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  def self.get(key, default = nil)
    find_by(key: key)&.value || default
  end

  def self.set(key, value)
    setting = find_or_initialize_by(key: key)
    setting.value = value
    setting.save!
    value
  end

  def self.unset(key)
    where(key: key).delete_all
  end

  def self.fetch(key, default = nil, &block)
    setting = find_by(key: key)
    return setting.value if setting

    value = block ? yield : default
    set(key, value) unless value.nil?
    value
  end
end
