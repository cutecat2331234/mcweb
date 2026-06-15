<script setup lang="ts">
import { computed } from 'vue'

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
  required?: boolean
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

const missingRequiredGroups = computed(() => {
  if (!props.tagGroups?.length) return []
  return props.tagGroups.filter((group) => {
    if (!group.required) return false
    const groupNames = new Set(group.tags.map((t) => t.name))
    return !selectedNames.value.some((name) => groupNames.has(name))
  })
})

const hasMissingRequired = computed(() => missingRequiredGroups.value.length > 0)
const isValid = computed(() => !hasMissingRequired.value)
const atMaxTags = computed(() => selectedNames.value.length >= (props.maxTags ?? 5))

defineExpose({ hasMissingRequired, isValid, missingRequiredGroups })

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
    if (names.length >= (props.maxTags ?? 5)) return
    names.push(name)
  }

  emit('update:modelValue', names.join(', '))
}
</script>

<template>
  <div class="space-y-3">
    <p v-if="missingRequiredGroups.length" class="rounded-md border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-900 dark:border-amber-800 dark:bg-amber-950 dark:text-amber-100">
      请从以下必填标签组中至少选一个标签：{{ missingRequiredGroups.map((g) => g.name).join('、') }}
    </p>
    <p v-if="atMaxTags" class="text-xs text-muted-foreground">已达标签上限（{{ maxTags ?? 5 }} 个）</p>
    <div v-for="group in tagGroups || []" :key="group.slug" class="rounded-md border p-3" :class="group.required ? 'border-amber-300/60' : ''">
      <div class="mb-2 flex items-center gap-2">
        <span
          v-if="group.color_hex"
          class="h-3 w-3 rounded-full"
          :style="{ backgroundColor: group.color_hex }"
        />
        <span class="text-sm font-medium">{{ group.name }}</span>
        <span v-if="group.required" class="text-xs text-amber-600">（必填组）</span>
        <span v-else-if="group.one_per_topic" class="text-xs text-muted-foreground">（每组限选一个）</span>
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
