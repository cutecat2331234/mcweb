class AuditLog < ApplicationRecord
  belongs_to :actor, class_name: "User", optional: true

  validates :action, presence: true

  before_update { throw(:abort) }
  before_destroy { throw(:abort) }

  scope :recent, -> { order(created_at: :desc) }
  scope :for_resource, ->(resource) { where(resource_type: resource.class.name, resource_id: resource.id) }
  scope :by_action, ->(action) { where(action: action) }

  def self.record!(action:, actor: nil, resource: nil, metadata: {}, before_state: {}, after_state: {}, **attrs)
    create!(
      action: action,
      actor: actor,
      resource_type: resource&.class&.name,
      resource_id: resource&.id,
      resource_public_id: resource.try(:public_id),
      metadata: metadata,
      before_state: before_state,
      after_state: after_state,
      **attrs
    )
  end
end
