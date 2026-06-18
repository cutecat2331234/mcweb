<script setup lang="ts">
import { computed } from 'vue'
import { ChevronRight } from '@lucide/vue'
import PortalNavLink from '@/components/portal/PortalNavLink.vue'
import { cn } from '@/lib/utils'
import type { PortalNavGroup } from '@/lib/usePortalNav'

const props = defineProps<{
  group: PortalNavGroup
  expanded: boolean
  isActive: (href: string) => boolean
}>()

const emit = defineEmits<{ toggle: []; navigate: [] }>()

const hasActiveChild = computed(() => props.group.items.some((item) => props.isActive(item.href)))
</script>

<template>
  <div>
    <button
      type="button"
      :class="cn(
        'mb-1 flex w-full items-center gap-2 rounded-lg px-3 py-1.5 text-left text-xs font-semibold uppercase tracking-wider transition-all duration-150',
        'hover:bg-sidebar-accent/40 active:scale-[0.99]',
        hasActiveChild ? 'text-sidebar-foreground' : 'text-sidebar-foreground/55',
      )"
      @click="emit('toggle')"
    >
      <ChevronRight
        class="h-3.5 w-3.5 shrink-0 transition-transform duration-200"
        :class="expanded && 'rotate-90'"
      />
      <span class="flex-1">{{ group.label }}</span>
      <span
        v-if="!expanded && hasActiveChild"
        class="h-1.5 w-1.5 shrink-0 rounded-full bg-primary"
        aria-hidden="true"
      />
    </button>

    <Transition
      enter-active-class="transition-all duration-200 ease-out overflow-hidden"
      enter-from-class="max-h-0 opacity-0"
      enter-to-class="max-h-[800px] opacity-100"
      leave-active-class="transition-all duration-150 ease-in overflow-hidden"
      leave-from-class="max-h-[800px] opacity-100"
      leave-to-class="max-h-0 opacity-0"
    >
      <div v-show="expanded" class="space-y-0.5 pb-1">
        <PortalNavLink
          v-for="item in group.items"
          :key="item.href"
          :item="item"
          :active="isActive(item.href)"
          @navigate="emit('navigate')"
        />
      </div>
    </Transition>
  </div>
</template>
