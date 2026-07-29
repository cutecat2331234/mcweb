class AuditLog < ApplicationRecord
  belongs_to :actor, class_name: "User", optional: true

  validates :action, presence: true
  validates :request_id, length: { maximum: 100 }, allow_blank: true

  before_update { throw(:abort) }
  before_destroy { throw(:abort) }

  scope :recent, -> { order(created_at: :desc) }
  scope :for_resource, ->(resource) { where(resource_type: resource.class.name, resource_id: resource.id) }
  scope :by_action, ->(action) { where(action: action) }
  scope :by_request_id, ->(request_id) { where(request_id: request_id.to_s.strip) }

  def self.record!(
    action:,
    actor: nil,
    resource: nil,
    metadata: {},
    before_state: {},
    after_state: {},
    request_id: nil,
    **attrs
  )
    create!(
      action: action,
      actor: actor,
      resource_type: resource&.class&.name,
      resource_id: resource&.id,
      resource_public_id: resource.try(:public_id),
      metadata: metadata,
      before_state: before_state,
      after_state: after_state,
      request_id: request_id.presence || metadata_request_id(metadata),
      **attrs
    )
  end

  def self.metadata_request_id(metadata)
    return unless metadata.respond_to?(:[])

    (metadata[:request_id] || metadata["request_id"] ||
      metadata[:requestId] || metadata["requestId"]).to_s.strip.first(100).presence
  end
  private_class_method :metadata_request_id
end
