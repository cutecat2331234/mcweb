class InstallationLock < ApplicationRecord
  belongs_to :locked_by, class_name: "User", optional: true

  def self.locked?
    current&.locked == true
  end

  def self.current
    order(created_at: :desc).first
  end

  def self.lock!(user: nil)
    record = current || create!
    record.update!(locked: true, locked_at: Time.current, locked_by: user)
    record
  end

  def self.unlock!
    current&.update!(locked: false, locked_at: nil, locked_by: nil)
  end
end
