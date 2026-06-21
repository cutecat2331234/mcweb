<script setup lang="ts">
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Textarea from '@/components/ui/Textarea.vue'
import Checkbox from '@/components/ui/Checkbox.vue'

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
}>()

function moveBlock(index: number, direction: -1 | 1) {
  const next = index + direction
  if (next < 0 || next >= props.blocks.length) return
  const ids = props.blocks.map((b) => b.id)
  ;[ids[index], ids[next]] = [ids[next], ids[index]]
  router.patch(`${props.baseUrl}/reorder`, { block_ids: ids }, { preserveScroll: true })
}

function addBlock() {
  router.post(props.baseUrl, {
    block: { block_type: 'hero', visible: true, settings: { headline: '', subheadline: '' } },
  }, { preserveScroll: true })
}

function updateBlock(block: BlockItem) {
  router.patch(`${props.baseUrl}/${block.id}`, { block }, { preserveScroll: true })
}

function removeBlock(id: number) {
  router.delete(`${props.baseUrl}/${id}`, { preserveScroll: true })
}
</script>

<template>
  <div class="space-y-4">
    <div v-for="(block, index) in blocks" :key="block.id" class="rounded-lg border p-4 space-y-3">
      <div class="flex flex-wrap items-center gap-2">
        <select v-model="block.block_type" class="rounded-md border bg-background px-2 py-1 text-sm">
          <option value="hero">Hero</option>
          <option value="rich_text">Rich text</option>
        </select>
        <label class="flex items-center gap-2 text-sm">
          <Checkbox v-model="block.visible" />
          {{ t('admin.common.visible', 'Visible') }}
        </label>
        <div class="ml-auto flex gap-1">
          <Button type="button" size="sm" variant="outline" :disabled="index === 0" @click="moveBlock(index, -1)">↑</Button>
          <Button type="button" size="sm" variant="outline" :disabled="index === blocks.length - 1" @click="moveBlock(index, 1)">↓</Button>
          <Button type="button" size="sm" variant="outline" @click="updateBlock(block)">{{ t('admin.ui.save') }}</Button>
          <Button type="button" size="sm" variant="destructive" @click="removeBlock(block.id)">{{ t('admin.ui.delete') }}</Button>
        </div>
      </div>
      <template v-if="block.block_type === 'hero'">
        <div class="space-y-2"><Label>Headline</Label><Input v-model="block.settings.headline" /></div>
        <div class="space-y-2"><Label>Subheadline</Label><Input v-model="block.settings.subheadline" /></div>
        <div class="space-y-2"><Label>CTA text</Label><Input v-model="block.settings.cta_text" /></div>
        <div class="space-y-2"><Label>CTA URL</Label><Input v-model="block.settings.cta_url" /></div>
      </template>
      <template v-else-if="block.block_type === 'rich_text'">
        <div class="space-y-2"><Label>HTML</Label><Textarea v-model="block.settings.html" rows="8" class="font-mono text-sm" /></div>
      </template>
    </div>
    <Button type="button" variant="outline" @click="addBlock">{{ t('admin.website.addBlock', 'Add block') }}</Button>
  </div>
</template>
