<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { ChevronDown, Check } from '@lucide/vue'
import { cn } from '@/lib/utils'

export interface SelectOption {
  value: string
  label: string
  description?: string
}

const props = withDefaults(
  defineProps<{
    modelValue: string
    options: SelectOption[]
    class?: string
    size?: 'sm' | 'default'
    disabled?: boolean
    title?: string
    block?: boolean
    id?: string
  }>(),
  { size: 'default', disabled: false, block: false },
)

const emit = defineEmits<{ 'update:modelValue': [value: string] }>()

const open = ref(false)
const root = ref<HTMLElement | null>(null)

const selected = computed(() => props.options.find((o) => o.value === props.modelValue))

function toggle() {
  if (props.disabled) return
  open.value = !open.value
}

function select(value: string) {
  emit('update:modelValue', value)
  open.value = false
}

function onClickOutside(event: MouseEvent) {
  if (!root.value?.contains(event.target as Node)) open.value = false
}

onMounted(() => document.addEventListener('click', onClickOutside))
onUnmounted(() => document.removeEventListener('click', onClickOutside))
</script>

<template>
  <div ref="root" :class="cn('relative text-left', block && 'block w-full')">
    <button
      :id="id"
      type="button"
      :disabled="disabled"
      :title="title || selected?.description"
      :class="cn(
        'inline-flex w-full items-center justify-between gap-2 rounded-md border border-input bg-background text-sm font-medium shadow-sm transition-all duration-150',
        'hover:bg-accent/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
        'active:scale-[0.98] disabled:pointer-events-none disabled:opacity-50',
        size === 'sm' ? 'h-8 px-2.5 text-xs' : 'h-9 px-3',
        block && 'w-full',
        props.class,
      )"
      @click.stop="toggle"
    >
      <span class="truncate">{{ selected?.label || '选择…' }}</span>
      <ChevronDown
        class="h-3.5 w-3.5 shrink-0 opacity-60 transition-transform duration-200"
        :class="open && 'rotate-180'"
      />
    </button>

    <Transition
      enter-active-class="transition duration-150 ease-out"
      enter-from-class="opacity-0 scale-95 -translate-y-1"
      enter-to-class="opacity-100 scale-100 translate-y-0"
      leave-active-class="transition duration-100 ease-in"
      leave-from-class="opacity-100 scale-100"
      leave-to-class="opacity-0 scale-95"
    >
      <ul
        v-if="open"
        class="absolute left-0 z-50 mt-1 min-w-full overflow-hidden rounded-md border border-border bg-popover py-1 text-popover-foreground shadow-md"
        role="listbox"
      >
        <li
          v-for="opt in options"
          :key="opt.value"
          role="option"
          :aria-selected="opt.value === modelValue"
          :title="opt.description"
          :class="cn(
            'flex cursor-pointer items-center justify-between gap-2 px-3 py-1.5 text-sm transition-colors duration-100',
            opt.value === modelValue
              ? 'bg-accent text-accent-foreground'
              : 'hover:bg-muted',
          )"
          @click.stop="select(opt.value)"
        >
          <span>{{ opt.label }}</span>
          <Check v-if="opt.value === modelValue" class="h-3.5 w-3.5 shrink-0 opacity-70" />
        </li>
      </ul>
    </Transition>
  </div>
</template>
