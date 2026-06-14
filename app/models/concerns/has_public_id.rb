module HasPublicId
  extend ActiveSupport::Concern

  included do
    before_validation :generate_public_id, on: :create
    validates :public_id, presence: true, uniqueness: true
  end

  class_methods do
    def find_by_public_id(public_id)
      find_by(public_id: public_id)
    end

    def find_by_public_id!(public_id)
      find_by!(public_id: public_id)
    end
  end

  private

  def generate_public_id
    return if public_id.present?

    loop do
      self.public_id = SecureRandom.urlsafe_base64(12)
      break unless self.class.exists?(public_id: public_id)
    end
  end
end
