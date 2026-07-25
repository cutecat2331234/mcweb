<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { adminRoutes } from '@/lib/adminRoutes'
import { confirm } from '@/lib/arcoConfirm'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

type Attachment = {
  id: number
  filename: string
  size: string
  content_type: string | null
  downloads: number
  uploader: string | null
  linked: boolean
  post_url: string | null
  created_at: string
  delete_url: string
}

type PaginationMeta = {
  page: number
  pages: number
  count: number
  from: number | null
  to: number | null
  prev: number | null
  next: number | null
}

const props = defineProps<{
  attachments: Attachment[]
  pagination: PaginationMeta
  filter: string
  orphanCount: number
  pruneUrl: string
}>()

function setFilter(value: string) {
  router.get(adminRoutes.forumAttachments, value ? { filter: value } : {}, { preserveState: true })
}

function visitPage(page: number) {
  router.get(
    adminRoutes.forumAttachments,
    { ...(props.filter ? { filter: props.filter } : {}), page },
    { preserveState: true, preserveScroll: true },
  )
}

async function removeAttachment(a: Attachment) {
  const ok = await confirm({
    title: t('admin.attachments.deleteTitle'),
    message: t('admin.attachments.deleteConfirm', { name: a.filename }),
    confirmLabel: t('admin.ui.delete'),
    variant: 'destructive',
  })
  if (!ok) return
  router.delete(a.delete_url, { preserveScroll: true })
}

async function prune() {
  const ok = await confirm({
    title: t('admin.attachments.pruneTitle'),
    message: t('admin.attachments.pruneConfirm', { count: props.orphanCount }),
    confirmLabel: t('admin.ui.delete'),
    variant: 'destructive',
  })
  if (!ok) return
  router.delete(props.pruneUrl)
}
</script>

<template>
  <a-page-header
    :title="t('admin.attachments.title')"
    :subtitle="t('admin.attachments.subtitle')"
    :show-back="false"
    class="mb-4 !px-0"
  >
    <template v-if="orphanCount > 0" #extra>
      <a-button type="primary" status="danger" size="small" @click="prune">
        {{ t('admin.attachments.prune', { count: orphanCount }) }}
      </a-button>
    </template>
  </a-page-header>

  <a-card class="mb-4" :bordered="true">
    <a-space wrap>
      <a-button :type="!filter ? 'primary' : 'outline'" @click="setFilter('')">
        {{ t('admin.attachments.tabAll') }}
      </a-button>
      <a-button
        :type="filter === 'orphans' ? 'primary' : 'outline'"
        @click="setFilter('orphans')"
      >
        {{ t('admin.attachments.tabOrphans') }} ({{ orphanCount }})
      </a-button>
    </a-space>
  </a-card>

  <a-card class="attachments-index__table-card" :bordered="true">
    <div class="overflow-x-auto">
      <a-table
        :data="attachments"
        :pagination="false"
        row-key="id"
        :bordered="{ cell: true }"
        stripe
      >
        <template #columns>
          <a-table-column :title="t('admin.attachments.colFile')" data-index="filename">
            <template #cell="{ record }"><strong>{{ record.filename }}</strong></template>
          </a-table-column>
          <a-table-column :title="t('admin.attachments.colSize')" data-index="size" />
          <a-table-column :title="t('admin.attachments.colUploader')" data-index="uploader">
            <template #cell="{ record }">{{ record.uploader ? `@${record.uploader}` : '—' }}</template>
          </a-table-column>
          <a-table-column :title="t('admin.attachments.colDownloads')" data-index="downloads" />
          <a-table-column :title="t('admin.attachments.colLinked')">
            <template #cell="{ record }">
              <Link
                v-if="record.linked && record.post_url"
                :href="record.post_url"
                class="text-[rgb(var(--primary-6))] no-underline hover:underline"
              >
                {{ t('admin.attachments.linked') }}
              </Link>
              <a-tag v-else color="orange">{{ t('admin.attachments.orphan') }}</a-tag>
            </template>
          </a-table-column>
          <a-table-column :width="100">
            <template #cell="{ record }">
              <a-button type="text" status="danger" size="small" @click="removeAttachment(record)">
                {{ t('admin.ui.delete') }}
              </a-button>
            </template>
          </a-table-column>
        </template>
        <template #empty><a-empty :description="t('admin.attachments.empty')" /></template>
      </a-table>
    </div>
  </a-card>

  <div
    v-if="pagination.pages > 1"
    class="mt-4 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"
  >
    <span class="text-sm text-[var(--color-text-3)]">
      {{ pagination.from }}–{{ pagination.to }} / {{ pagination.count }}
    </span>
    <a-pagination
      :current="pagination.page"
      :total="pagination.pages"
      :page-size="1"
      :show-page-size="false"
      @change="visitPage"
    />
  </div>
</template>

<style scoped>
.attachments-index__table-card :deep(.arco-card-body) {
  padding: 0;
}
</style>
