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
  <a-card :title="title" :bordered="true">
    <a-empty v-if="!points.length" :description="t('adminMinecraft.noMetricHistory')" />
    <template v-else>
      <a-grid :cols="{ xs: 1, sm: 2, md: 4 }" :col-gap="12" :row-gap="12">
        <a-grid-item>
          <a-statistic
            :title="t('adminMinecraft.metricCpu')"
            :value="latest?.cpu_percent ?? 0"
            :precision="1"
            suffix="%"
          />
        </a-grid-item>
        <a-grid-item>
          <a-statistic
            :title="t('adminMinecraft.metricMem')"
            :value="formatBytes(latest?.mem_used_bytes)"
          />
        </a-grid-item>
        <a-grid-item>
          <a-statistic
            :title="t('adminMinecraft.metricTps')"
            :value="latest?.tps ?? 0"
            :precision="2"
          />
        </a-grid-item>
        <a-grid-item>
          <a-statistic
            :title="t('adminMinecraft.metricPlayers')"
            :value="`${latest?.online_players ?? '—'}/${latest?.max_players ?? '—'}`"
          />
        </a-grid-item>
      </a-grid>
      <a-divider />
      <a-typography-text type="secondary">
        {{ t('adminMinecraft.metricPoints', { count: points.length }) }}
      </a-typography-text>
    </template>
  </a-card>
</template>
