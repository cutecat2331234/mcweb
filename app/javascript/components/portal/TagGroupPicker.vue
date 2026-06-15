<script setup lang="ts">
import { computed } from 'vue'
import { Link } from '@inertiajs/vue3'

export interface TagOption {
  name: string
  slug: string
  color_hex?: string | null
}

export interface TagGroupOption {
  name: string
  slug: string
  color_hex?: string | null
  one_per_topic: boolean
  tags: TagOption[]
}

const props = defineProps<{
  modelValue: string
  tagGroups?: TagGroupOption[]
  maxTags?: number
}>()

const emit = defineEmits<{
  'update:modelValue': [value: string]
}>()

const selectedNames = computed(() =>
  props.modelValue
    .split(',')
    .map((t) => t.trim())
    .filter(Boolean)
)

function isSelected(name: string) {
  return selectedNames.value.includes(name)
}

function toggleTag(name: string, group?: TagGroupOption) {
  let names = [...selectedNames.value]
  const idx = names.indexOf(name)

  if (idx >= 0) {
    names.splice(idx, 1)
  } else {
    if (group?.one_per_topic) {
      const groupNames = new Set(group.tags.map((t) => t.name))
      names = names.filter((n) => !groupNames.has(n))
    }
    const max = props.maxTags ?? 5
    if (names.length >= max) return
    names.push(name)
  }

  emit('update:modelValue', names.join(', '))
}
</script>

<template>
  <div class="space-y-3">
    <div v-for="group in tagGroups || []" :key="group.slug" class="rounded-md border p-3">
      <div class="mb-2 flex items-center gap-2">
        <span
          v-if="group.color_hex"
          class="h-3 w-3 rounded-full"
          :style="{ backgroundColor: group.color_hex }"
        />
        <span class="text-sm font-medium">{{ group.name }}</span>
        <span v-if="group.one_per_topic" class="text-xs text-muted-foreground">（每组限选一个）</span>
      </div>
      <div class="flex flex-wrap gap-2">
        <button
          v-for="tag in group.tags"
          :key="tag.slug"
          type="button"
          class="rounded-full border px-2 py-0.5 text-xs transition-colors"
          :class="isSelected(tag.name) ? 'border-primary bg-primary/10' : 'hover:bg-muted'"
          :style="tag.color_hex && !isSelected(tag.name) ? { borderColor: tag.color_hex, color: tag.color_hex } : undefined"
          @click="toggleTag(tag.name, group)"
        >
          #{{ tag.name }}
        </button>
      </div>
    </div>
    <div class="space-y-1">
      <label class="text-xs text-muted-foreground">已选标签（可手动编辑）</label>
      <input
        :value="modelValue"
        class="h-9 w-full rounded-md border px-2 text-sm"
        placeholder="例如：公告,活动"
        @input="emit('update:modelValue', ($event.target as HTMLInputElement).value)"
      />
    </div>
    <p v-if="!tagGroups?.length" class="text-xs text-muted-foreground">
      暂无标签组，请使用逗号分隔输入标签。
    </p>
  </div>
</template>
