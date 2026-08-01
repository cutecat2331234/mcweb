<script setup lang="ts">
import { router } from '@inertiajs/vue3'
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

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

const columns = computed(() => [
  { title: t('admin.website.revisions.revision'), dataIndex: 'revision_number', slotName: 'revision', width: 120 },
  { title: t('admin.website.revisions.author'), dataIndex: 'author', slotName: 'author' },
  { title: t('admin.website.revisions.createdAt'), dataIndex: 'created_at' },
  { title: '', slotName: 'actions', width: 100 },
])
</script>

<template>
  <a-space direction="vertical" :size="24" fill>
    <a-page-header :title="title" :subtitle="page.title" :show-back="false">
      <template #extra>
        <a-button @click="router.visit(backUrl)">{{ t('common.back') }}</a-button>
      </template>
    </a-page-header>

    <a-row justify="center">
      <a-col :xs="24" :md="22" :xl="18">
        <a-card size="small" :bordered="true">
          <a-table
            :columns="columns"
            :data="revisions"
            row-key="id"
            size="small"
            :pagination="false"
            :scroll="{ x: 700 }"
          >
            <template #revision="{ record }">
              <a-tag color="arcoblue">#{{ record.revision_number }}</a-tag>
            </template>
            <template #author="{ record }">
              <a-typography-text>{{ record.author || '—' }}</a-typography-text>
            </template>
            <template #actions="{ record }">
              <a-button
                type="text"
                size="small"
                @click="router.visit(record.url)"
              >
                {{ t('common.view') }}
              </a-button>
            </template>
            <template #empty>
              <a-empty :description="t('admin.ui.noResults')" />
            </template>
          </a-table>
        </a-card>
      </a-col>
    </a-row>
  </a-space>
</template>
