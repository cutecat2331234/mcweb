<script setup lang="ts">
import { AlertCircle, CheckCircle2, Info } from '@lucide/vue'
import { cn } from '@/lib/utils'

withDefaults(
  defineProps<{
    variant?: 'default' | 'destructive' | 'success'
    title?: string
    class?: string
  }>(),
  { variant: 'default' },
)

const icons = {
  default: Info,
  destructive: AlertCircle,
  success: CheckCircle2,
}
</script>

<template>
  <div
    role="alert"
    :class="cn(
      'flex gap-3 rounded-lg border px-4 py-3 text-sm',
      variant === 'destructive' && 'border-destructive/40 bg-destructive/10 text-destructive',
      variant === 'success' && 'border-emerald-500/40 bg-emerald-500/10 text-emerald-800 dark:text-emerald-200',
      variant === 'default' && 'border-border bg-muted/40 text-foreground',
      props.class,
    )"
  >
    <component :is="icons[variant]" class="mt-0.5 h-4 w-4 shrink-0" />
    <div class="min-w-0 space-y-1">
      <p v-if="title" class="font-medium leading-none">{{ title }}</p>
      <div class="text-sm leading-relaxed">
        <slot />
      </div>
    </div>
  </div>
</template>
