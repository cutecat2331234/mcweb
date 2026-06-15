<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import TopicTitleBadges from '@/components/portal/TopicTitleBadges.vue'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'

export interface TopicListItem {
  id: string
  title: string
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
  tags?: Array<{ name: string; slug: string; url: string }>
  participant_avatars?: Array<{ username: string; avatar_url: string; profile_url: string }>
}

defineProps<{
  topics: TopicListItem[]
  showViews?: boolean
  showParticipants?: boolean
}>()
</script>

<template>
  <div v-if="topics.length" class="rounded-lg border">
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>主题</TableHead>
          <TableHead>作者</TableHead>
          <TableHead>回复</TableHead>
          <TableHead v-if="showViews">浏览</TableHead>
          <TableHead>最后回复</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        <TableRow v-for="topic in topics" :key="topic.id">
          <TableCell>
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
              :tags="topic.tags"
            />
            <Link :href="topic.url" class="font-medium hover:underline">{{ topic.title }}</Link>
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
    暂无主题。
  </p>
</template>
