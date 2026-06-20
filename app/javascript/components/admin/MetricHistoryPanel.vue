<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'

export interface MetricPoint {
  at: string
  cpu_percent?: number | null
  mem_used_bytes?: number | null
  disk_used_bytes?: number | null
  tps?: number | null
  online_players?: number | null
  max_players?: number | null
}

const props = defineProps<{
  points: MetricPoint[]
  title: string
}>()

const { t } = useI18n()

const latest = computed(() => props.points[props.points.length - 1])

function formatBytes(bytes?: number | null) {
  if (bytes == null) return '—'
  const gb = bytes / (1024 * 1024 * 1024)
  return `${gb.toFixed(1)} GB`
}
</script>

<template>
  <section class="max-w-2xl">
    <h2 class="mb-3 text-lg font-semibold">{{ title }}</h2>
    <p v-if="!points.length" class="text-sm text-muted-foreground">{{ t('adminMinecraft.noMetricHistory') }}</p>
    <template v-else>
      <dl class="mb-4 grid grid-cols-2 gap-3 text-sm md:grid-cols-4">
        <div>
          <dt class="text-muted-foreground">{{ t('adminMinecraft.metricCpu') }}</dt>
          <dd class="font-medium">{{ latest?.cpu_percent?.toFixed?.(1) ?? '—' }}%</dd>
        </div>
        <div>
          <dt class="text-muted-foreground">{{ t('adminMinecraft.metricMem') }}</dt>
          <dd class="font-medium">{{ formatBytes(latest?.mem_used_bytes) }}</dd>
        </div>
        <div>
          <dt class="text-muted-foreground">{{ t('adminMinecraft.metricTps') }}</dt>
          <dd class="font-medium">{{ latest?.tps?.toFixed?.(2) ?? '—' }}</dd>
        </div>
        <div>
          <dt class="text-muted-foreground">{{ t('adminMinecraft.metricPlayers') }}</dt>
          <dd class="font-medium">{{ latest?.online_players ?? '—' }}/{{ latest?.max_players ?? '—' }}</dd>
        </div>
      </dl>
      <p class="text-xs text-muted-foreground">{{ t('adminMinecraft.metricPoints', { count: points.length }) }}</p>
    </template>
  </section>
</template>
