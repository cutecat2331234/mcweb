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

  def soft_delete!
    update_column(:deleted_at, Time.current)
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
