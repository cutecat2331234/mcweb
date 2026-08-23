<script setup lang="ts">
import { computed, ref } from 'vue'
import type { Page } from '@inertiajs/core'
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import { Modal } from '@arco-design/web-vue'
import { IconArrowDown, IconArrowUp, IconDelete, IconEdit } from '@arco-design/web-vue/es/icon'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

interface NavItem {
  id: number
  label: string
  url: string | null
  website_page_id: number | null
  page_public_id: string | null
  location: string
  visible: boolean
  position: number
  href: string
}

const props = defineProps<{
  title: string
  items: NavItem[]
  pages: Array<{ id: string; title: string; slug: string }>
  submitUrl: string
  reorderUrl: string
  canEdit: boolean
}>()

const locations = ['header', 'footer'] as const
const draft = ref({
  label: '',
  url: '',
  website_page_id: '',
  location: 'header',
  visible: true,
})
const editingId = ref<number | null>(null)
const pageOptions = computed(() => [
  { value: '', label: t('admin.website.nav.externalUrl') },
  ...props.pages.map((page) => ({
    value: page.id,
    label: `${page.title} (/${page.slug})`,
  })),
])
const locationOptions = computed(() =>
  locations.map((value) => ({
    value,
    label: t(`admin.website.nav.locations.${value}`),
  })),
)

function locationLabel(location: (typeof locations)[number]) {
  return t(`admin.website.nav.locations.${location}`)
}

function itemsForLocation(location: string) {
  return props.items.filter((item) => item.location === location)
}

function rowsForLocation(location: string) {
  return itemsForLocation(location).map((item, index) => ({ ...item, index }))
}

function resetDraft() {
  editingId.value = null
  draft.value = {
    label: '',
    url: '',
    website_page_id: '',
    location: 'header',
    visible: true,
  }
}

function requestSucceeded(page: Page) {
  const flash = page.props.flash as { notice?: string | null } | undefined
  return Boolean(flash?.notice)
}

function saveItem() {
  if (!props.canEdit) return

  const data = {
    nav_item: {
      ...draft.value,
      website_page_id: draft.value.website_page_id || null,
      url: draft.value.url || null,
    },
  }
  const options = {
    preserveScroll: true,
    onSuccess: (page: Page) => {
      if (requestSucceeded(page)) resetDraft()
    },
  }
  if (editingId.value === null) {
    router.post(props.submitUrl, data, options)
  } else {
    router.patch(`${props.submitUrl}/${editingId.value}`, data, options)
  }
}

function startEditing(item: NavItem) {
  if (!props.canEdit) return

  editingId.value = item.id
  draft.value = {
    label: item.label,
    url: item.url || '',
    website_page_id: item.page_public_id || '',
    location: item.location,
    visible: item.visible,
  }
}

function removeItem(item: NavItem) {
  if (!props.canEdit) return

  Modal.warning({
    title: t('admin.ui.delete'),
    content: t('admin.website.nav.deleteConfirm', { label: item.label }),
    okText: t('admin.ui.delete'),
    cancelText: t('admin.ui.cancel'),
    hideCancel: false,
    okButtonProps: { status: 'danger' },
    onOk: () => router.delete(`${props.submitUrl}/${item.id}`, {
      preserveScroll: true,
      onSuccess: (page) => {
        if (requestSucceeded(page) && editingId.value === item.id) resetDraft()
      },
    }),
  })
}

function moveItem(location: string, index: number, direction: -1 | 1) {
  if (!props.canEdit) return

  const group = itemsForLocation(location)
  const next = index + direction
  if (next < 0 || next >= group.length) return
  const ids = group.map((item) => item.id)
  ;[ids[index], ids[next]] = [ids[next], ids[index]]
  router.patch(props.reorderUrl, { item_ids: ids, location }, { preserveScroll: true })
}

const columns = computed(() => [
  { title: t('admin.common.title'), dataIndex: 'label', width: 180 },
  { title: t('admin.website.nav.url'), dataIndex: 'href' },
  { title: t('admin.common.visible'), slotName: 'visible', width: 100 },
  ...(props.canEdit
    ? [{ title: t('adminMinecraft.actions'), slotName: 'actions', width: 240 }]
    : []),
])
</script>

<template>
  <a-space direction="vertical" :size="16" fill>
    <a-page-header :title="title" :show-back="false" />

  <a-card
    v-if="canEdit"
    :title="editingId === null ? t('admin.website.nav.add') : t('admin.ui.edit')"
    :bordered="true"
  >
    <a-form :model="draft" layout="vertical" @submit="saveItem">
      <a-grid :cols="{ xs: 1, md: 2 }" :col-gap="16">
        <a-grid-item>
          <a-form-item field="label" :label="t('admin.website.nav.label')" required>
            <a-input v-model="draft.label" allow-clear />
          </a-form-item>
        </a-grid-item>
        <a-grid-item>
          <a-form-item field="location" :label="t('admin.website.nav.location')">
            <a-select v-model="draft.location" :options="locationOptions" />
          </a-form-item>
        </a-grid-item>
        <a-grid-item>
          <a-form-item field="website_page_id" :label="t('admin.website.nav.page')">
            <a-select
              v-model="draft.website_page_id"
              :options="pageOptions"
              allow-search
              allow-clear
            />
          </a-form-item>
        </a-grid-item>
        <a-grid-item v-if="!draft.website_page_id">
          <a-form-item field="url" :label="t('admin.website.nav.url')">
            <a-input v-model="draft.url" placeholder="/blog" allow-clear />
          </a-form-item>
        </a-grid-item>
      </a-grid>
      <a-form-item field="visible" :label="t('admin.common.visible')">
        <a-switch v-model="draft.visible" />
      </a-form-item>
      <a-space wrap>
        <a-button html-type="submit" type="primary" :disabled="!draft.label.trim()">
          {{ t('admin.ui.save') }}
        </a-button>
        <a-button v-if="editingId !== null" html-type="button" @click="resetDraft">
          {{ t('admin.ui.cancel') }}
        </a-button>
      </a-space>
    </a-form>
  </a-card>

  <a-space direction="vertical" fill>
    <a-card
      v-for="location in locations"
      :key="location"
      :title="locationLabel(location)"
      :bordered="true"
    >
      <a-table
        :columns="columns"
        :data="rowsForLocation(location)"
        row-key="id"
        :pagination="false"
        :scroll="{ x: 680 }"
      >
        <template #visible="{ record }">
          <a-tag :color="record.visible ? 'green' : 'gray'">
            {{ record.visible ? t('adminMinecraft.yes') : t('adminMinecraft.no') }}
          </a-tag>
        </template>
        <template v-if="canEdit" #actions="{ record }">
          <a-space>
            <a-button
              size="small"
              :aria-label="t('admin.ui.edit')"
              @click="startEditing(record)"
            >
              <template #icon><icon-edit /></template>
            </a-button>
            <a-button
              size="small"
              :disabled="record.index === 0"
              :aria-label="t('common.moveUp', 'Move up')"
              @click="moveItem(location, record.index, -1)"
            >
              <template #icon><icon-arrow-up /></template>
            </a-button>
            <a-button
              size="small"
              :disabled="record.index === rowsForLocation(location).length - 1"
              :aria-label="t('common.moveDown', 'Move down')"
              @click="moveItem(location, record.index, 1)"
            >
              <template #icon><icon-arrow-down /></template>
            </a-button>
            <a-button size="small" status="danger" @click="removeItem(record)">
              <template #icon><icon-delete /></template>
            </a-button>
          </a-space>
        </template>
        <template #empty><a-empty /></template>
      </a-table>
    </a-card>
  </a-space>
  </a-space>
</template>
