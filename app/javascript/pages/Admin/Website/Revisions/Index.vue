<script setup lang="ts">
import { computed } from 'vue'
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()
defineProps<{
  title: string
  content: { id: string; type: 'page' | 'article'; title: string; slug: string; status: string }
  revisions: Array<{
    id: number
    revision_number: number
    event_type: string
    reason: string | null
    source_lock_version: number
    author: string | null
    created_at: string
    url: string
  }>
  backUrl: string
}>()

const columns = computed(() => [
  { title: t('admin.website.revisions.revision'), dataIndex: 'revision_number', slotName: 'revision', width: 110 },
  { title: t('admin.website.revisions.event'), dataIndex: 'event_type', slotName: 'event', width: 150 },
  { title: t('admin.website.revisions.author'), dataIndex: 'author', width: 150 },
  { title: t('admin.website.revisions.reason'), dataIndex: 'reason', width: 260 },
  { title: t('admin.website.revisions.createdAt'), dataIndex: 'created_at', width: 190 },
  { title: '', slotName: 'actions', width: 100 },
])
</script>

<template>
  <a-space direction="vertical" :size="16" fill>
    <a-page-header :title="title" :subtitle="content.title" :show-back="false">
      <template #extra>
        <a-button @click="router.visit(backUrl)">{{ t('common.back') }}</a-button>
      </template>
    </a-page-header>
    <a-card :bordered="true">
      <a-table
        :columns="columns"
        :data="revisions"
        row-key="id"
        :pagination="{ pageSize: 25, showTotal: true }"
        :scroll="{ x: 960 }"
      >
        <template #revision="{ record }"><a-tag color="arcoblue">#{{ record.revision_number }}</a-tag></template>
        <template #event="{ record }">{{ t(`admin.website.revisions.events.${record.event_type}`, record.event_type) }}</template>
        <template #actions="{ record }">
          <a-button type="text" size="small" @click="router.visit(record.url)">{{ t('common.view') }}</a-button>
        </template>
        <template #empty><a-empty :description="t('admin.ui.noResults')" /></template>
      </a-table>
    </a-card>
  </a-space>
</template>
