<script setup lang="ts">
import { ref } from 'vue'
import { Link, router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Badge from '@/components/ui/Badge.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Textarea from '@/components/ui/Textarea.vue'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

defineProps<{
  topics: Array<{
    bookmark_id: number
    update_url: string
    note: string | null
    remind_at: string | null
    remind_at_input?: string | null
    topic: {
      id: string
      title: string
      url: string
      author: string | null
      replies_count: number
      last_posted_at: string | null
      has_unread: boolean
      unread_count: number
    }
  }>
  postBookmarks: Array<{
    id: number
    bookmark_id: number
    update_url: string
    note: string | null
    floor_number: number
    excerpt: string
    topic_title: string
    url: string
    created_at: string
  }>
}>()

const editingId = ref<number | null>(null)
const editNote = ref('')
const editRemindAt = ref('')

function startEdit(id: number, note: string | null, remindAtInput: string | null | undefined) {
  editingId.value = id
  editNote.value = note || ''
  editRemindAt.value = remindAtInput || ''
}

function saveBookmark(url: string) {
  router.patch(url, {
    bookmark: {
      note: editNote.value,
      remind_at: editRemindAt.value || null,
    },
  }, {
    preserveScroll: true,
    onSuccess: () => { editingId.value = null },
  })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: '我的书签', current: true },
  ]" />

  <PageHeader title="我的书签" subtitle="收藏的主题与帖子，可添加备注与提醒" />

  <section v-if="postBookmarks.length" class="mb-8">
    <h2 class="mb-3 text-sm font-semibold">帖子书签</h2>
    <div class="rounded-lg border">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>主题</TableHead>
            <TableHead>楼层</TableHead>
            <TableHead>备注</TableHead>
            <TableHead>收藏时间</TableHead>
            <TableHead />
          </TableRow>
        </TableHeader>
        <TableBody>
          <TableRow v-for="bookmark in postBookmarks" :key="bookmark.bookmark_id">
            <TableCell>
              <Link :href="bookmark.url" class="font-medium hover:underline">{{ bookmark.topic_title }}</Link>
            </TableCell>
            <TableCell>#{{ bookmark.floor_number }}</TableCell>
            <TableCell class="max-w-xs text-muted-foreground">{{ bookmark.note || bookmark.excerpt }}</TableCell>
            <TableCell>{{ bookmark.created_at }}</TableCell>
            <TableCell>
              <Button type="button" variant="outline" size="sm" @click="startEdit(bookmark.bookmark_id, bookmark.note, null)">编辑</Button>
            </TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </div>
  </section>

  <section>
    <h2 class="mb-3 text-sm font-semibold">主题书签</h2>
    <div v-if="topics.length" class="space-y-3">
      <article v-for="item in topics" :key="item.bookmark_id" class="rounded-lg border p-4">
        <div class="flex flex-wrap items-start justify-between gap-2">
          <div>
            <Link :href="item.topic.url" class="font-medium hover:underline">{{ item.topic.title }}</Link>
            <Badge v-if="item.topic.has_unread" class="ml-2">{{ item.topic.unread_count }} 未读</Badge>
            <p class="mt-1 text-xs text-muted-foreground">
              {{ item.topic.author || '—' }} · {{ item.topic.replies_count }} 回复 · {{ item.topic.last_posted_at || '—' }}
            </p>
            <p v-if="item.note" class="mt-2 text-sm text-muted-foreground">备注：{{ item.note }}</p>
            <p v-if="item.remind_at" class="text-xs text-muted-foreground">提醒：{{ item.remind_at }}</p>
          </div>
          <Button type="button" variant="outline" size="sm" @click="startEdit(item.bookmark_id, item.note, item.remind_at_input)">编辑备注</Button>
        </div>
        <div v-if="editingId === item.bookmark_id" class="mt-3 space-y-2 border-t pt-3">
          <Textarea v-model="editNote" rows="2" placeholder="书签备注" />
          <Input v-model="editRemindAt" type="datetime-local" />
          <div class="flex gap-2">
            <Button type="button" size="sm" @click="saveBookmark(item.update_url)">保存</Button>
            <Button type="button" size="sm" variant="outline" @click="editingId = null">取消</Button>
          </div>
        </div>
      </article>
    </div>
    <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
      你还没有收藏任何主题。
    </p>
  </section>
</template>
