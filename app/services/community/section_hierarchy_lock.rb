# frozen_string_literal: true

module Community
  # Locks one or more section ancestry chains in a deterministic order.
  #
  # All forum writes and lifecycle mutations use this entry point so an
  # ancestor cannot be archived between an access check and the content write.
  # Callers must already be inside a database transaction.
  module SectionHierarchyLock
    class HierarchyChanged < StandardError; end
    class TopicSectionChanged < StandardError; end

    module_function

    def lock!(*sections)
      requested = sections.flatten.compact
      return [] if requested.empty?

      requested_ids = requested.map(&:id)
      raise ArgumentError, "persisted sections are required" if requested_ids.any?(&:blank?)

      discovered_ids = ancestry_ids_for(requested_ids)
      locked_by_id = {}
      discovered_ids.sort.each do |id|
        locked_by_id[id] = Community::Section.lock.find(id)
      end

      locked_sections = requested_ids.map { |id| locked_by_id.fetch(id) }
      actual_ids = ancestry_ids_for(locked_sections.map(&:id))
      raise HierarchyChanged unless actual_ids.sort == discovered_ids.sort

      locked_sections
    end

    # Locks the topic's current section hierarchy before the topic row. If a
    # concurrent move committed between the initial read and these locks, the
    # caller must roll back and retry from the topic's new section.
    def lock_topic!(topic, *additional_sections)
      expected_section_id = topic.forum_section_id
      expected_section = Community::Section.find(expected_section_id)
      locked_sections = lock!(expected_section, *additional_sections)
      topic.lock!
      raise TopicSectionChanged unless topic.forum_section_id == expected_section_id

      topic.association(:section).target = locked_sections.first
      [ topic, *locked_sections ]
    end

    # Locks every involved section hierarchy before taking topic-row locks in
    # stable ID order. Multi-topic mutations must use this method instead of
    # locking topics first, otherwise they can deadlock with replies and moves
    # that correctly take section locks before topic locks.
    def lock_topics!(*topics, additional_sections: [])
      requested_topics = topics.flatten.compact
      return [] if requested_topics.empty?

      topic_ids = requested_topics.map(&:id)
      raise ArgumentError, "persisted topics are required" if topic_ids.any?(&:blank?)

      expected_section_ids = requested_topics.to_h do |topic|
        [ topic.id, topic.forum_section_id ]
      end
      source_sections = Community::Section.where(id: expected_section_ids.values.uniq).index_by(&:id)
      raise ActiveRecord::RecordNotFound unless source_sections.size == expected_section_ids.values.uniq.size

      locked_sections = lock!(
        *expected_section_ids.values.map { |section_id| source_sections.fetch(section_id) },
        *Array(additional_sections)
      )
      locked_sections_by_id = locked_sections.index_by(&:id)
      locked_topics_by_id = Community::Topic.with_discarded
        .where(id: topic_ids.uniq)
        .order(:id)
        .lock
        .index_by(&:id)
      raise ActiveRecord::RecordNotFound unless locked_topics_by_id.size == topic_ids.uniq.size

      requested_topics.map do |requested_topic|
        locked_topic = locked_topics_by_id.fetch(requested_topic.id)
        expected_section_id = expected_section_ids.fetch(requested_topic.id)
        raise TopicSectionChanged unless locked_topic.forum_section_id == expected_section_id

        locked_topic.association(:section).target = locked_sections_by_id.fetch(expected_section_id)
        locked_topic
      end
    end

    def ancestry_ids_for(section_ids)
      pending = Array(section_ids).map(&:to_i).reject(&:zero?).uniq
      discovered = []

      while pending.any?
        current_ids = pending - discovered
        break if current_ids.empty?

        discovered.concat(current_ids)
        pending = Community::Section.where(id: current_ids).where.not(parent_id: nil).pluck(:parent_id).uniq
      end

      discovered.uniq
    end
    private_class_method :ancestry_ids_for
  end
end
