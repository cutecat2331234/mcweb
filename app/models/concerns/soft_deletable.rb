module SoftDeletable
  extend ActiveSupport::Concern

  included do
    scope :kept, -> { where(deleted_at: nil) }
    scope :discarded, -> { where.not(deleted_at: nil) }
    default_scope { kept }
  end

  def deleted?
    deleted_at.present?
  end

  # Some governed models also expose a `deleted` enum value, which generates a
  # `deleted?` method after this concern is included. Lifecycle code must use
  # this unambiguous predicate instead of depending on method-definition order.
  def soft_deleted?
    deleted_at.present?
  end

  def soft_delete!(at: Time.current)
    update_column(:deleted_at, at)
  end

  def restore!
    update_column(:deleted_at, nil)
  end

  class_methods do
    def with_discarded
      unscope(where: :deleted_at)
    end
  end
end
