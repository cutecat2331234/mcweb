<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import { routes } from '@/lib/routes'
import { confirm } from '@/lib/useConfirm'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

defineProps<{
  post: {
    id: number
    floor_number: number
    topic_url: string
  }
  edits: Array<{
    id: number
    editor: string
    body_before: string
    body_after: string
    diff_lines: Array<{ kind: string; text: string }>
    reason?: string | null
    created_at: string
    restore_url?: string | null
  }>
  can_restore?: boolean
}>()

async function restoreEdit(url: string | null | undefined) {
  const ok = await confirm({
    title: t('forum.postEdits.restoreTitle'),
    message: t('forum.postEdits.restoreConfirm'),
    confirmLabel: t('forum.postEdits.restore'),
  })
  if (!url || !ok) return
  router.post(url, {}, { preserveScroll: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.forum'), href: routes.forum },
    { label: t('forum.postEdits.breadcrumb', { floor: post.floor_number }), current: true },
  ]" />

  <PageHeader :title="t('forum.postEdits.title', { floor: post.floor_number })" />

  <div v-if="edits.length" class="space-y-4">
    <article v-for="(edit, i) in edits" :key="i" class="rounded-lg border p-4">
      <p class="mb-2 text-sm text-muted-foreground">
        {{ edit.editor }} · {{ edit.created_at }}
        <span v-if="edit.reason" class="ml-2">{{ t('forum.postEdits.reason', { reason: edit.reason }) }}</span>
        <Button v-if="edit.restore_url" type="button" variant="outline" size="sm" class="ml-2" @click="restoreEdit(edit.restore_url)">
          {{ t('forum.postEdits.restoreVersion') }}
        </Button>
      </p>
      <div v-if="edit.diff_lines.length" class="mb-3 space-y-1 rounded bg-muted p-3 font-mono text-xs">
        <div
          v-for="(line, j) in edit.diff_lines"
          :key="j"
          :class="{
            'text-red-600 line-through': line.kind === 'removed',
            'text-green-600': line.kind === 'added',
            'text-muted-foreground': line.kind === 'same',
          }"
        >
          <span v-if="line.kind === 'removed'">− </span>
          <span v-else-if="line.kind === 'added'">+ </span>
          <span v-else>  </span>{{ line.text }}
        </div>
      </div>
      <div class="grid gap-4 md:grid-cols-2">
        <div>
          <p class="mb-1 text-xs font-semibold text-muted-foreground">{{ t('forum.postEdits.before') }}</p>
          <pre class="whitespace-pre-wrap rounded bg-muted p-3 text-sm">{{ edit.body_before }}</pre>
        </div>
        <div>
          <p class="mb-1 text-xs font-semibold text-muted-foreground">{{ t('forum.postEdits.after') }}</p>
          <pre class="whitespace-pre-wrap rounded bg-muted p-3 text-sm">{{ edit.body_after }}</pre>
        </div>
      </div>
    </article>
  </div>
  <p v-else class="text-sm text-muted-foreground">{{ t('forum.postEdits.empty') }}</p>

  <Link :href="post.topic_url" class="mt-6 inline-block text-sm hover:underline">{{ t('forum.postEdits.backToTopic') }}</Link>
</template>
