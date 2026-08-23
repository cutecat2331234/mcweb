<script setup lang="ts">
import { computed, ref } from 'vue'
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()
const props = defineProps<{
  title: string
  rows: Array<{
    id: string
    type: 'page' | 'article'
    type_label: string
    title: string
    slug: string
    discarded_by: string | null
    discarded_at: string
    purge_at: string
    reason: string
    url: string
  }>
  pagesUrl: string | null
  articlesUrl: string | null
}>()

const typeFilter = ref('all')
const visibleRows = computed(() => typeFilter.value === 'all'
  ? props.rows
  : props.rows.filter((row) => row.type === typeFilter.value))
const typeOptions = computed(() => [
  { value: 'all', label: t('admin.website.recovery.all_types') },
  { value: 'page', label: t('admin.website.recovery.types.page') },
  { value: 'article', label: t('admin.website.recovery.types.article') },
])
const columns = computed(() => [
  { title: t('admin.website.recovery.type'), dataIndex: 'type_label', width: 110 },
  { title: t('admin.website.recovery.content_title'), dataIndex: 'title', slotName: 'title', width: 220 },
  { title: t('admin.website.recovery.slug'), dataIndex: 'slug', width: 180 },
  { title: t('admin.website.recovery.discarded_by'), dataIndex: 'discarded_by', width: 150 },
  { title: t('admin.website.recovery.discarded_at'), dataIndex: 'discarded_at', width: 190 },
  { title: t('admin.website.recovery.purge_deadline'), dataIndex: 'purge_at', width: 190 },
])
</script>

<template>
  <a-space direction="vertical" :size="16" fill>
    <a-page-header :title="title" :show-back="false">
      <template #extra>
        <a-space wrap>
          <a-button v-if="pagesUrl" @click="router.visit(pagesUrl)">{{ t('admin.pages') }}</a-button>
          <a-button v-if="articlesUrl" @click="router.visit(articlesUrl)">{{ t('admin.articles') }}</a-button>
        </a-space>
      </template>
    </a-page-header>

    <a-card :bordered="true">
      <a-space direction="vertical" fill>
        <a-select v-model="typeFilter" :options="typeOptions" />
        <a-table
          :columns="columns"
          :data="visibleRows"
          row-key="id"
          :pagination="{ pageSize: 25, showTotal: true }"
          :scroll="{ x: 1040 }"
        >
          <template #title="{ record }">
            <a-link @click="router.visit(record.url)">{{ record.title }}</a-link>
          </template>
          <template #empty>
            <a-empty :description="t('admin.website.recovery.empty')" />
          </template>
        </a-table>
      </a-space>
    </a-card>
  </a-space>
</template>
