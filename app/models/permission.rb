class Permission < ApplicationRecord
  has_many :role_permissions, dependent: :destroy
  has_many :roles, through: :role_permissions

  validates :key, presence: true, uniqueness: true,
                  format: { with: /\A[a-z][a-z0-9_.]*\z/ }
  validates :name, presence: true
  validates :category, presence: true

  scope :by_category, ->(category) { where(category: category) }
end
