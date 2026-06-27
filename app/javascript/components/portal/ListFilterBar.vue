<script setup lang="ts">
import { useI18n } from 'vue-i18n'

export interface ActiveFilterChip {
  param: string
  label: string
  value?: string
}

withDefaults(
  defineProps<{
    /** Active-filter chips rendered below the controls row. Pass [] / undefined to hide. */
    activeFilters?: ActiveFilterChip[]
  }>(),
  { activeFilters: () => [] },
)

const emit = defineEmits<{
  'remove-filter': [chip: ActiveFilterChip]
}>()

const { t } = useI18n()
</script>

<template>
  <div class="mb-4 space-y-3">
    <!--
      Controls row.

      The wrapping bug came from `flex flex-wrap items-center gap-4` laying out
      several independent label+control groups with a large gap, which on narrow
      widths broke into a ragged multi-line block. Here the controls live on a
      single non-wrapping line that becomes horizontally scrollable on small
      screens (no ragged wrap), with a tight `gap-2`. Each item is `shrink-0`
      and aligned to a consistent `h-8`, so nothing gets squished and the bar
      stays tidy on desktop and reachable on mobile (375px).
    -->
    <div
      v-if="$slots.default || $slots.period || $slots.actions || $slots.rss"
      class="-mx-1 flex flex-nowrap items-center gap-2 overflow-x-auto px-1 py-0.5 [scrollbar-width:thin] [&>*]:shrink-0"
    >
      <slot name="period" />
      <slot />
      <slot name="actions" />
      <!-- Push the RSS link to the trailing edge when present. -->
      <div v-if="$slots.rss" class="ml-auto flex items-center gap-2 pl-2">
        <slot name="rss" />
      </div>
    </div>

    <!-- Active-filter chips. Chips are allowed to wrap (that reads fine). -->
    <div
      v-if="activeFilters.length || $slots['chips-actions']"
      class="flex flex-wrap items-center gap-2"
    >
      <span v-if="activeFilters.length" class="text-xs text-muted-foreground">
        {{ t('forum.lists.activeFilters') }}
      </span>
      <slot name="chips-actions" />
      <span
        v-for="chip in activeFilters"
        :key="`${chip.param}-${chip.value || chip.label}`"
        class="inline-flex items-center gap-1 rounded-full border border-primary/30 bg-primary/5 px-2.5 py-0.5 text-xs text-primary"
      >
        {{ chip.label }}
        <button
          type="button"
          class="hover:opacity-70"
          :title="t('forum.lists.removeFilter')"
          @click="emit('remove-filter', chip)"
        >×</button>
      </span>
    </div>
  </div>
</template>
