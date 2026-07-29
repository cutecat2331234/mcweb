<script setup lang="ts">
import { router } from '@inertiajs/vue3'
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

defineProps<{
  title: string
  page: { id: string; title: string }
  revisions: Array<{
    id: number
    revision_number: number
    author: string | null
    created_at: string
    url: string
  }>
  backUrl: string
}>()

const { t } = useI18n()
const columns = computed(() => [
  { title: t('admin.website.revisions.revision'), dataIndex: 'revision_number', slotName: 'revision', width: 120 },
  { title: t('admin.website.revisions.author'), dataIndex: 'author', slotName: 'author' },
  { title: t('admin.website.revisions.createdAt'), dataIndex: 'created_at' },
  { title: '', slotName: 'actions', width: 100 },
])
</script>

<template>
  <a-page-header :title="title" :subtitle="page.title" :show-back="false">
    <template #extra>
      <a-button @click="router.visit(backUrl)">{{ t('common.back') }}</a-button>
    </template>
  </a-page-header>
  <a-card :bordered="true">
    <a-table
      :columns="columns"
      :data="revisions"
      row-key="id"
      :pagination="false"
      :scroll="{ x: 600 }"
    >
      <template #revision="{ record }">#{{ record.revision_number }}</template>
      <template #author="{ record }">{{ record.author || '—' }}</template>
      <template #actions="{ record }">
        <a-button type="text" size="small" @click="router.visit(record.url)">
          {{ t('common.view') }}
        </a-button>
      </template>
      <template #empty><a-empty /></template>
    </a-table>
  </a-card>
</template>
