<script setup lang="ts">
import { computed, ref } from 'vue'
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import TopicListTable, { type TopicListItem } from '@/components/portal/TopicListTable.vue'
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

const { t } = useI18n()

const props = defineProps<{
  topics: Array<{
    bookmark_id: number
    update_url: string
    note: string | null
    label?: string | null
    remind_at: string | null
    remind_at_input?: string | null
    topic: TopicListItem
  }>
  postBookmarks: Array<{
    id: number
    bookmark_id: number
    update_url: string
    note: string | null
    label?: string | null
    remind_at?: string | null
    remind_at_input?: string | null
    floor_number: number
    excerpt: string
    topic_title: string
    url: string
    created_at: string
  }>
  labels?: string[]
  activeLabel?: string
}>()

const topicItems = computed(() => props.topics.map((item) => item.topic))

const editingId = ref<number | null>(null)
const editNote = ref('')
const editRemindAt = ref('')
const editLabel = ref('')

function startEdit(id: number, note: string | null, remindAtInput: string | null | undefined, label: string | null | undefined) {
  editingId.value = id
  editNote.value = note || ''
  editRemindAt.value = remindAtInput || ''
  editLabel.value = label || ''
}

function saveBookmark(url: string) {
  router.patch(url, {
    bookmark: {
      note: editNote.value,
      remind_at: editRemindAt.value || null,
      label: editLabel.value,
    },
  }, {
    preserveScroll: true,
    onSuccess: () => { editingId.value = null },
  })
}

function filterByLabel(label: string | null) {
  router.get(routes.forumBookmarks, label ? { label } : {}, { preserveState: true, preserveScroll: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.forum'), href: routes.forum },
    { label: t('forum.bookmarks.breadcrumb'), current: true },
  ]" />

  <PageHeader :title="t('forum.bookmarks.title')" :subtitle="t('forum.bookmarks.subtitle')" />

  <div v-if="labels?.length" class="mb-4 flex flex-wrap items-center gap-2">
    <span class="text-xs text-muted-foreground">{{ t('forum.bookmarks.labelFilter') }}</span>
    <Button :variant="!activeLabel ? 'default' : 'outline'" size="sm" @click="filterByLabel(null)">{{ t('forum.bookmarks.allLabels') }}</Button>
    <Button
      v-for="label in labels"
      :key="label"
      :variant="activeLabel === label ? 'default' : 'outline'"
      size="sm"
      @click="filterByLabel(label)"
    >
      {{ label }}
    </Button>
  </div>

  <section v-if="postBookmarks.length" class="mb-8">
    <h2 class="mb-3 text-sm font-semibold">{{ t('forum.bookmarks.postBookmarks') }}</h2>
    <div class="rounded-lg border">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>{{ t('forum.bookmarks.topicCol') }}</TableHead>
            <TableHead>{{ t('forum.bookmarks.floorCol') }}</TableHead>
            <TableHead>{{ t('forum.bookmarks.noteCol') }}</TableHead>
            <TableHead>{{ t('forum.bookmarks.remindCol') }}</TableHead>
            <TableHead>{{ t('forum.bookmarks.savedAtCol') }}</TableHead>
            <TableHead />
          </TableRow>
        </TableHeader>
        <TableBody>
          <template v-for="bookmark in postBookmarks" :key="bookmark.bookmark_id">
            <TableRow>
              <TableCell>
                <Link :href="bookmark.url" class="font-medium hover:underline">{{ bookmark.topic_title }}</Link>
              </TableCell>
              <TableCell>#{{ bookmark.floor_number }}</TableCell>
              <TableCell class="max-w-xs text-muted-foreground">
                <span v-if="bookmark.label" class="mr-2 inline-block rounded-full border border-primary/30 bg-primary/5 px-2 py-0.5 text-xs text-primary">{{ bookmark.label }}</span>
                {{ bookmark.note || bookmark.excerpt }}
              </TableCell>
              <TableCell>{{ bookmark.remind_at || '—' }}</TableCell>
              <TableCell>{{ bookmark.created_at }}</TableCell>
              <TableCell>
                <Button type="button" variant="outline" size="sm" @click="startEdit(bookmark.bookmark_id, bookmark.note, bookmark.remind_at_input, bookmark.label)">{{ t('forum.lists.edit') }}</Button>
              </TableCell>
            </TableRow>
            <TableRow v-if="editingId === bookmark.bookmark_id">
              <TableCell colspan="6" class="space-y-2 border-t bg-muted/30 p-4">
                <Textarea v-model="editNote" rows="2" :placeholder="t('forum.bookmarks.notePlaceholder')" />
                <Input v-model="editLabel" :placeholder="t('forum.bookmarks.labelPlaceholder')" maxlength="40" />
                <Input v-model="editRemindAt" type="datetime-local" />
                <div class="flex gap-2">
                  <Button type="button" size="sm" @click="saveBookmark(bookmark.update_url)">{{ t('forum.lists.save') }}</Button>
                  <Button type="button" size="sm" variant="outline" @click="editingId = null">{{ t('forum.lists.cancel') }}</Button>
                </div>
              </TableCell>
            </TableRow>
          </template>
        </TableBody>
      </Table>
    </div>
  </section>

  <section>
    <h2 class="mb-3 text-sm font-semibold">{{ t('forum.bookmarks.topicBookmarks') }}</h2>
    <TopicListTable v-if="topicItems.length" :topics="topicItems" show-views show-participants class="mb-4" />
    <div v-if="topics.length" class="space-y-3">
      <article
        v-for="item in topics"
        :key="item.bookmark_id"
        class="rounded-lg border p-4"
      >
        <div class="flex flex-wrap items-start justify-between gap-2">
          <div class="min-w-0 flex-1">
            <p v-if="item.label" class="mb-1">
              <span class="inline-block rounded-full border border-primary/30 bg-primary/5 px-2 py-0.5 text-xs text-primary">{{ item.label }}</span>
            </p>
            <p v-if="item.note" class="text-sm text-muted-foreground">{{ t('forum.bookmarks.notePrefix') }}{{ item.note }}</p>
            <p v-if="item.remind_at" class="text-xs text-muted-foreground">{{ t('forum.bookmarks.remindPrefix') }}{{ item.remind_at }}</p>
            <p v-if="!item.note && !item.remind_at && !item.label" class="text-xs text-muted-foreground">{{ t('forum.bookmarks.noNoteRemind') }}</p>
          </div>
          <Button type="button" variant="outline" size="sm" @click="startEdit(item.bookmark_id, item.note, item.remind_at_input, item.label)">{{ t('forum.bookmarks.editNote') }}</Button>
        </div>
        <div v-if="editingId === item.bookmark_id" class="mt-3 space-y-2 border-t pt-3">
          <Textarea v-model="editNote" rows="2" :placeholder="t('forum.bookmarks.notePlaceholder')" />
          <Input v-model="editLabel" :placeholder="t('forum.bookmarks.labelPlaceholder')" maxlength="40" />
          <Input v-model="editRemindAt" type="datetime-local" />
          <div class="flex gap-2">
            <Button type="button" size="sm" @click="saveBookmark(item.update_url)">{{ t('forum.lists.save') }}</Button>
            <Button type="button" size="sm" variant="outline" @click="editingId = null">{{ t('forum.lists.cancel') }}</Button>
          </div>
        </div>
      </article>
    </div>
    <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
      {{ t('forum.bookmarks.emptyTopics') }}
    </p>
  </section>
</template>
