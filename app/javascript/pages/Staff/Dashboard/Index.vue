<script setup lang="ts">
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  Alert,
  Button,
  Card,
  Grid,
  GridItem,
  PageHeader,
  Space,
  Statistic,
  Table,
  TableColumn,
  Tag,
  TypographyParagraph,
  TypographyText,
} from '@mcweb/ui'
import { IconArrowRight, IconSafe } from '@arco-design/web-vue/es/icon'
import StaffLayout from '@/layouts/StaffLayout.vue'

defineOptions({ layout: StaffLayout })

type ModerationCase = {
  id: number
  source_kind: string
  status: string
  priority: string
  risk_level: string
  title: string
  section: { id?: number; name?: string } | null
  assignee: { id?: number; username?: string; name?: string } | null
  updated_at: string
}

const props = defineProps<{
  metrics: {
    active: number
    unassigned: number
    assigned_to_me: number
    high_risk: number
  }
  source_counts: Record<string, number>
  recent_cases: ModerationCase[]
  links: {
    queue: string
    my_queue: string
    unassigned: string
    high_risk: string
  }
  sync_warning?: string | null
}>()

const { locale, t } = useI18n()

function formatTime(value: string) {
  return new Intl.DateTimeFormat(locale.value, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value))
}

function riskColor(value: string) {
  if (value === 'critical' || value === 'high') return 'red'
  if (value === 'medium') return 'orange'
  return 'blue'
}

function openCase(id: number) {
  router.visit(`${props.links.queue}?case_id=${id}`)
}
</script>

<template>
  <Space direction="vertical" fill size="large">
    <PageHeader
      :show-back="false"
      :title="t('staffWorkspace.dashboard.title')"
      :subtitle="t('staffWorkspace.dashboard.subtitle')"
    >
      <template #extra>
        <Button type="primary" shape="round" @click="router.visit(links.queue)">
          <template #icon><IconSafe /></template>
          {{ t('staffWorkspace.dashboard.openQueue') }}
        </Button>
      </template>
    </PageHeader>

    <Alert v-if="sync_warning" type="warning" show-icon>
      {{ t('staffWorkspace.syncWarning') }}
    </Alert>

    <Grid :cols="{ xs: 1, sm: 2, lg: 4 }" :col-gap="12" :row-gap="12">
      <GridItem>
        <Card hoverable :style="{ borderRadius: '14px' }" @click="router.visit(links.queue)">
          <Statistic :title="t('staffWorkspace.metrics.active')" :value="metrics.active" />
        </Card>
      </GridItem>
      <GridItem>
        <Card hoverable :style="{ borderRadius: '14px' }" @click="router.visit(links.unassigned)">
          <Statistic :title="t('staffWorkspace.metrics.unassigned')" :value="metrics.unassigned" />
        </Card>
      </GridItem>
      <GridItem>
        <Card hoverable :style="{ borderRadius: '14px' }" @click="router.visit(links.my_queue)">
          <Statistic :title="t('staffWorkspace.metrics.mine')" :value="metrics.assigned_to_me" />
        </Card>
      </GridItem>
      <GridItem>
        <Card hoverable :style="{ borderRadius: '14px' }" @click="router.visit(links.high_risk)">
          <Statistic
            :title="t('staffWorkspace.metrics.highRisk')"
            :value="metrics.high_risk"
            :value-style="metrics.high_risk > 0 ? { color: 'rgb(var(--red-6))' } : undefined"
          />
        </Card>
      </GridItem>
    </Grid>

    <Grid :cols="{ xs: 1, lg: 4 }" :col-gap="12" :row-gap="12">
      <GridItem :span="{ xs: 1, lg: 3 }">
        <Card :bordered="true" :style="{ borderRadius: '8px' }">
          <template #title>{{ t('staffWorkspace.dashboard.recentCases') }}</template>
          <template #extra>
            <Button type="text" @click="router.visit(links.queue)">
              {{ t('staffWorkspace.dashboard.viewAll') }}
              <template #icon><IconArrowRight /></template>
            </Button>
          </template>
          <Table
            :data="recent_cases"
            :pagination="false"
            row-key="id"
            :bordered="{ wrapper: true }"
            :scroll="{ minWidth: 780 }"
            @row-click="(record) => openCase(record.id)"
          >
            <template #columns>
              <TableColumn :title="t('staffWorkspace.cases.case')" :width="96">
                <template #cell="{ record }">#{{ record.id }}</template>
              </TableColumn>
              <TableColumn :title="t('staffWorkspace.cases.title')" data-index="title" :width="260" />
              <TableColumn :title="t('staffWorkspace.cases.source')" :width="150">
                <template #cell="{ record }">
                  {{ t(`staffWorkspace.sourceKinds.${record.source_kind}`) }}
                </template>
              </TableColumn>
              <TableColumn :title="t('staffWorkspace.cases.risk')" :width="120">
                <template #cell="{ record }">
                  <Tag :color="riskColor(record.risk_level)">
                    {{ t(`staffWorkspace.riskLevels.${record.risk_level}`) }}
                  </Tag>
                </template>
              </TableColumn>
              <TableColumn :title="t('staffWorkspace.cases.updated')" :width="190">
                <template #cell="{ record }">{{ formatTime(record.updated_at) }}</template>
              </TableColumn>
            </template>
          </Table>
        </Card>
      </GridItem>

      <GridItem :span="{ xs: 1, lg: 1 }">
        <Card :bordered="true" :style="{ borderRadius: '14px' }">
          <template #title>{{ t('staffWorkspace.dashboard.sourceSummary') }}</template>
          <Space v-if="Object.keys(source_counts).length" direction="vertical" fill>
            <Space
              v-for="(count, source) in source_counts"
              :key="source"
              align="center"
              justify="space-between"
              fill
            >
              <TypographyText>{{ t(`staffWorkspace.sourceKinds.${source}`) }}</TypographyText>
              <Tag bordered>{{ count }}</Tag>
            </Space>
          </Space>
          <TypographyParagraph v-else type="secondary">
            {{ t('staffWorkspace.dashboard.noActiveCases') }}
          </TypographyParagraph>
        </Card>
      </GridItem>
    </Grid>
  </Space>
</template>
