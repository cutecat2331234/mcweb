# frozen_string_literal: true

module InertiaSerializable
  extend ActiveSupport::Concern

  private

  def pagy_props(pagy)
    {
      page: pagy.page,
      pages: pagy.pages,
      count: pagy.count,
      from: pagy.from,
      to: pagy.to,
      prev: pagy.prev,
      next: pagy.next
    }
  end

  def inertia_user
    return nil unless current_user

    {
      id: current_user.public_id,
      username: current_user.username,
      email: current_user.email
    }
  end

  def serialize_section(section)
    {
      id: section.id,
      name: section.name,
      slug: section.slug,
      description: section.description&.truncate(80),
      category_name: section.category&.name,
      url: forum_section_path(section)
    }
  end

  def serialize_topic(topic)
    {
      id: topic.public_id,
      title: topic.title,
      url: forum_topic_path(topic),
      author: topic.user&.username,
      replies_count: topic.replies_count,
      last_posted_at: topic.last_posted_at ? l(topic.last_posted_at, format: :short) : nil,
      pinned: topic.pinned?,
      locked: topic.locked?
    }
  end

  def serialize_product_list_item(product)
    {
      id: product.public_id,
      name: product.name,
      slug: product.slug,
      category_name: product.category&.name,
      price_label: format_price(product),
      in_stock: product.in_stock?,
      url: store_product_path(product)
    }
  end

  def serialize_product_detail(product)
    {
      id: product.public_id,
      db_id: product.id,
      name: product.name,
      slug: product.slug,
      description: product.description,
      price_label: format_price(product),
      product_type: product.product_type,
      category_name: product.category&.name,
      in_stock: product.in_stock?
    }
  end

  def serialize_article(article)
    {
      id: article.public_id,
      title: article.title,
      slug: article.slug,
      excerpt: article.summary,
      published_at: article.published_at&.iso8601
    }
  end

  def format_price(product)
    unit = product.currency == "CNY" ? "¥" : "$"
    ActionController::Base.helpers.number_to_currency(product.price, unit: unit)
  end
end
