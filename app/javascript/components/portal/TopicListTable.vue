<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import { Link } from '@inertiajs/vue3'
import TopicTitleBadges from '@/components/portal/TopicTitleBadges.vue'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'
import Checkbox from '@/components/ui/Checkbox.vue'

const { t } = useI18n()

export interface TopicListItem {
  id: string
  title: string
  title_html?: string | null
  url: string
  author: string | null
  replies_count: number
  views_count?: number
  last_posted_at?: string | null
  last_poster_username?: string | null
  last_poster_url?: string | null
  pinned?: boolean
  featured?: boolean
  locked?: boolean
  solved?: boolean
  wiki?: boolean
  global_announcement?: boolean
  unlisted?: boolean
  archived?: boolean
  prefix?: string | null
  has_unread?: boolean
  unread_count?: number
  linked_product?: boolean
  linked_product_name?: string | null
  linked_product_url?: string | null
  assigned_username?: string | null
  assigned_url?: string | null
  tags?: Array<{ name: string; slug: string; url: string; color_hex?: string | null; group_color_hex?: string | null }>
  participant_avatars?: Array<{ username: string; avatar_url: string; profile_url: string }>
  excerpt?: string | null
  thumbnail_url?: string | null
}

const props = defineProps<{
  topics: TopicListItem[]
  showViews?: boolean
  showParticipants?: boolean
  selectable?: boolean
  selectedIds?: string[]
}>()

const emit = defineEmits<{
  'update:selectedIds': [ids: string[]]
}>()

function toggleRow(id: string, checked: boolean) {
  const current = new Set(props.selectedIds || [])
  if (checked) current.add(id)
  else current.delete(id)
  emit('update:selectedIds', Array.from(current))
}

function toggleAll(checked: boolean) {
  emit('update:selectedIds', checked ? props.topics.map((t) => t.id) : [])
}

const allSelected = () =>
  props.topics.length > 0 && props.topics.every((t) => (props.selectedIds || []).includes(t.id))
</script>

<template>
  <div v-if="topics.length" class="rounded-lg border">
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead v-if="selectable" class="w-10">
            <Checkbox
              :model-value="allSelected()"
              @update:model-value="toggleAll"
            />
          </TableHead>
          <TableHead>{{ t('components.topicList.colTopic') }}</TableHead>
          <TableHead>{{ t('components.topicList.colAuthor') }}</TableHead>
          <TableHead>{{ t('components.topicList.colReplies') }}</TableHead>
          <TableHead v-if="showViews">{{ t('components.topicList.colViews') }}</TableHead>
          <TableHead>{{ t('components.topicList.colLastReply') }}</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        <TableRow v-for="topic in topics" :key="topic.id">
          <TableCell v-if="selectable" class="w-10">
            <Checkbox
              :model-value="(selectedIds || []).includes(topic.id)"
              @update:model-value="(checked) => toggleRow(topic.id, checked)"
            />
          </TableCell>
          <TableCell>
            <div class="flex gap-3">
              <img
                v-if="topic.thumbnail_url"
                :src="topic.thumbnail_url"
                alt=""
                class="mt-0.5 h-12 w-12 shrink-0 rounded object-cover"
              />
              <div class="min-w-0 flex-1">
            <TopicTitleBadges
              :prefix="topic.prefix"
              :pinned="topic.pinned"
              :featured="topic.featured"
              :locked="topic.locked"
              :solved="topic.solved"
              :wiki="topic.wiki"
              :global-announcement="topic.global_announcement"
              :unlisted="topic.unlisted"
              :archived="topic.archived"
              :has-unread="topic.has_unread"
              :unread-count="topic.unread_count"
              :linked-product="topic.linked_product"
              :linked-product-name="topic.linked_product_name"
              :linked-product-url="topic.linked_product_url"
              :assigned-username="topic.assigned_username"
              :assigned-url="topic.assigned_url"
              :tags="topic.tags"
            />
            <Link v-if="!topic.title_html" :href="topic.url" class="font-medium hover:underline">{{ topic.title }}</Link>
            <Link v-else :href="topic.url" class="font-medium hover:underline"><span v-html="topic.title_html" /></Link>
            <p v-if="topic.excerpt" class="mt-1 line-clamp-2 text-xs text-muted-foreground">{{ topic.excerpt }}</p>
            <div v-if="showParticipants && topic.participant_avatars?.length" class="mt-1 flex items-center gap-1">
              <img
                v-for="avatar in topic.participant_avatars"
                :key="avatar.username"
                :src="avatar.avatar_url"
                :alt="avatar.username"
                :title="avatar.username"
                class="h-5 w-5 rounded-full border"
              />
            </div>
              </div>
            </div>
          </TableCell>
          <TableCell>{{ topic.author || '—' }}</TableCell>
          <TableCell>{{ topic.replies_count }}</TableCell>
          <TableCell v-if="showViews">{{ topic.views_count ?? '—' }}</TableCell>
          <TableCell>
            <template v-if="topic.last_poster_username && topic.last_poster_url">
              <Link :href="topic.last_poster_url" class="hover:underline">@{{ topic.last_poster_username }}</Link>
            </template>
            <span v-else>{{ topic.last_posted_at || '—' }}</span>
            <p v-if="topic.last_poster_username" class="text-xs text-muted-foreground">{{ topic.last_posted_at || '—' }}</p>
          </TableCell>
        </TableRow>
      </TableBody>
    </Table>
  </div>
  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
    {{ t('components.topicList.empty') }}
  </p>
</template>
