<script setup lang="ts">
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import { Modal } from '@mcweb/ui'
import { IconArrowDown, IconArrowUp, IconDelete, IconPlus } from '@arco-design/web-vue/es/icon'
import { createIdempotencyKey } from '@/lib/idempotency'

const { t } = useI18n()

export interface BlockItem {
  id: number
  block_type: string
  position: number
  visible: boolean
  settings: Record<string, string>
}

const props = defineProps<{
  blocks: BlockItem[]
  baseUrl: string
  pageLockVersion: number
}>()

const blockTypeOptions = [
  { value: 'hero', label: t('admin.website.blocks.types.hero') },
  { value: 'rich_text', label: t('admin.website.blocks.types.richText') },
]

function moveBlock(index: number, direction: -1 | 1) {
  const next = index + direction
  if (next < 0 || next >= props.blocks.length) return
  const ids = props.blocks.map((block) => block.id)
  ;[ids[index], ids[next]] = [ids[next], ids[index]]
  router.patch(
    `${props.baseUrl}/reorder`,
    { block_ids: ids, request_id: createIdempotencyKey(), lock_version: props.pageLockVersion },
    { preserveScroll: true },
  )
}

function addBlock() {
  router.post(
    props.baseUrl,
    {
      block: {
        block_type: 'hero',
        visible: true,
        settings: { headline: '', subheadline: '' },
      },
      request_id: createIdempotencyKey(),
      lock_version: props.pageLockVersion,
    },
    { preserveScroll: true },
  )
}

function updateBlock(block: BlockItem) {
  router.patch(
    `${props.baseUrl}/${block.id}`,
    { block, request_id: createIdempotencyKey(), lock_version: props.pageLockVersion },
    { preserveScroll: true },
  )
}

function removeBlock(block: BlockItem) {
  Modal.warning({
    title: t('admin.ui.delete'),
    content: t('admin.website.deleteBlockConfirm', `Delete block #${block.id}?`),
    okText: t('admin.ui.delete'),
    cancelText: t('admin.ui.cancel'),
    hideCancel: false,
    okButtonProps: { status: 'danger' },
    onOk: () => router.visit(`${props.baseUrl}/${block.id}`, {
      method: 'delete',
      data: { request_id: createIdempotencyKey(), lock_version: props.pageLockVersion },
      preserveScroll: true,
    }),
  })
}
</script>

<template>
  <a-space direction="vertical" fill>
    <a-card
      v-for="(block, index) in blocks"
      :key="block.id"
      :title="`#${block.id}`"
      :bordered="true"
    >
      <template #extra>
        <a-space wrap>
          <a-button
            size="small"
            :disabled="index === 0"
            :aria-label="t('common.moveUp', 'Move up')"
            @click="moveBlock(index, -1)"
          >
            <template #icon><icon-arrow-up /></template>
          </a-button>
          <a-button
            size="small"
            :disabled="index === blocks.length - 1"
            :aria-label="t('common.moveDown', 'Move down')"
            @click="moveBlock(index, 1)"
          >
            <template #icon><icon-arrow-down /></template>
          </a-button>
          <a-button size="small" type="primary" @click="updateBlock(block)">
            {{ t('admin.ui.save') }}
          </a-button>
          <a-button size="small" status="danger" @click="removeBlock(block)">
            <template #icon><icon-delete /></template>
            {{ t('admin.ui.delete') }}
          </a-button>
        </a-space>
      </template>

      <a-form :model="block" layout="vertical">
        <a-grid :cols="{ xs: 1, sm: 2 }" :col-gap="16">
          <a-grid-item>
            <a-form-item field="block_type" :label="t('admin.website.blocks.type')">
              <a-select v-model="block.block_type" :options="blockTypeOptions" />
            </a-form-item>
          </a-grid-item>
          <a-grid-item>
            <a-form-item field="visible" :label="t('admin.common.visible', 'Visible')">
              <a-switch v-model="block.visible" />
            </a-form-item>
          </a-grid-item>
        </a-grid>

        <template v-if="block.block_type === 'hero'">
          <a-form-item field="settings.headline" :label="t('admin.website.blocks.headline')">
            <a-input v-model="block.settings.headline" allow-clear />
          </a-form-item>
          <a-form-item field="settings.subheadline" :label="t('admin.website.blocks.subheadline')">
            <a-input v-model="block.settings.subheadline" allow-clear />
          </a-form-item>
          <a-form-item field="settings.cta_text" :label="t('admin.website.blocks.ctaText')">
            <a-input v-model="block.settings.cta_text" allow-clear />
          </a-form-item>
          <a-form-item field="settings.cta_url" :label="t('admin.website.blocks.ctaUrl')">
            <a-input v-model="block.settings.cta_url" allow-clear />
          </a-form-item>
        </template>
        <a-form-item v-else-if="block.block_type === 'rich_text'" field="settings.html" :label="t('admin.website.blocks.html')">
          <a-textarea
            v-model="block.settings.html"
            class="font-mono"
            :auto-size="{ minRows: 8, maxRows: 20 }"
          />
        </a-form-item>
      </a-form>
    </a-card>

    <a-button type="outline" @click="addBlock">
      <template #icon><icon-plus /></template>
      {{ t('admin.website.addBlock', 'Add block') }}
    </a-button>
  </a-space>
</template>
