<script setup lang="ts">
import { computed, watch } from 'vue'
import { useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  Alert,
  Button,
  Card,
  Grid,
  GridItem,
  InputNumber,
  PageHeader,
  Space,
  Statistic,
  Table,
  TableColumn,
  Tag,
  TypographyText,
} from '@mcweb/ui'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

type Dimension = 'account' | 'ip'
type NumericValue = number | undefined
type FormPolicies = Record<string, Record<Dimension, {
  limit: NumericValue
  window_seconds: NumericValue
}>>

interface PolicyRow {
  id: string
  action: string
  dimension: Dimension
  limit: number
  window_seconds: number
  active_counters: number
  blocked_requests: number
  last_blocked_at: string | null
}

interface Props {
  rows: PolicyRow[]
  summary: {
    configured_dimensions: number
    active_counters: number
    blocked_requests: number
  }
  formValues: FormPolicies
  formErrors: Record<string, string>
  constraints: {
    limit: { min: number; max: number }
    windowSeconds: { min: number; max: number }
  }
  updateUrl: string
}

const props = defineProps<Props>()
const { t, locale } = useI18n()

function clonePolicies(values: FormPolicies): FormPolicies {
  return JSON.parse(JSON.stringify(values)) as FormPolicies
}

const form = useForm<{ policies: FormPolicies }>({
  policies: clonePolicies(props.formValues),
})

watch(
  () => props.formValues,
  (values) => {
    if (!form.processing) form.policies = clonePolicies(values)
  },
  { deep: true },
)

const rows = computed(() => props.rows)

function fieldError(row: PolicyRow, attribute: 'limit' | 'window_seconds') {
  return props.formErrors[`policies.${row.action}.${row.dimension}.${attribute}`] || ''
}

function formatDate(value: string | null) {
  if (!value) return t('admin.rateLimits.never')

  return new Intl.DateTimeFormat(locale.value, {
    dateStyle: 'short',
    timeStyle: 'short',
  }).format(new Date(value))
}

function submit() {
  form.patch(props.updateUrl, {
    preserveScroll: true,
  })
}
</script>

<template>
  <section class="admin-rate-limits">
    <PageHeader
      :title="t('admin.rateLimits.title')"
      :subtitle="t('admin.rateLimits.subtitle')"
      :show-back="false"
      class="mb-5 !px-0"
    />

    <Alert
      type="info"
      :title="t('admin.rateLimits.privacyNotice')"
      show-icon
      class="mb-5"
    />

    <Grid
      :cols="{ xs: 1, sm: 3 }"
      :col-gap="16"
      :row-gap="16"
      class="mb-5"
    >
      <GridItem>
        <Card :bordered="false" class="rate-limit-stat">
          <Statistic
            :title="t('admin.rateLimits.configuredDimensions')"
            :value="summary.configured_dimensions"
          />
        </Card>
      </GridItem>
      <GridItem>
        <Card :bordered="false" class="rate-limit-stat">
          <Statistic
            :title="t('admin.rateLimits.activeCounters')"
            :value="summary.active_counters"
          />
        </Card>
      </GridItem>
      <GridItem>
        <Card :bordered="false" class="rate-limit-stat">
          <Statistic
            :title="t('admin.rateLimits.blockedRequests')"
            :value="summary.blocked_requests"
          />
        </Card>
      </GridItem>
    </Grid>

    <Card :bordered="false" class="rate-limit-panel">
      <form @submit.prevent="submit">
        <TypographyText type="secondary" class="rate-limit-scroll-hint">
          {{ t('admin.rateLimits.scrollHint') }}
        </TypographyText>
        <div class="rate-limit-table-scroll">
          <Table
            :data="rows"
            :pagination="false"
            :bordered="{ wrapper: true }"
            :scroll="{ minWidth: 1120 }"
            row-key="id"
          >
            <template #columns>
              <TableColumn :title="t('admin.rateLimits.action')" data-index="action" :width="170">
                <template #cell="{ record }">
                  <TypographyText class="font-medium">
                    {{ t(`admin.rateLimits.actions.${record.action}`) }}
                  </TypographyText>
                </template>
              </TableColumn>

              <TableColumn :title="t('admin.rateLimits.dimension')" data-index="dimension" :width="120">
                <template #cell="{ record }">
                  <Tag :color="record.dimension === 'account' ? 'arcoblue' : 'purple'">
                    {{ t(`admin.rateLimits.dimensions.${record.dimension}`) }}
                  </Tag>
                </template>
              </TableColumn>

              <TableColumn :title="t('admin.rateLimits.limit')" :width="180">
                <template #cell="{ record }">
                  <div class="rate-limit-field">
                    <InputNumber
                      v-model="form.policies[record.action][record.dimension].limit"
                      :min="constraints.limit.min"
                      :max="constraints.limit.max"
                      :precision="0"
                      :error="Boolean(fieldError(record, 'limit'))"
                      hide-button
                      class="w-full"
                      :aria-label="`${t(`admin.rateLimits.actions.${record.action}`)} ${t('admin.rateLimits.limit')}`"
                    />
                    <TypographyText
                      v-if="fieldError(record, 'limit')"
                      type="danger"
                      class="rate-limit-error"
                    >
                      {{ fieldError(record, 'limit') }}
                    </TypographyText>
                    <TypographyText v-else type="secondary" class="rate-limit-help">
                      {{ t('admin.rateLimits.zeroDisables') }}
                    </TypographyText>
                  </div>
                </template>
              </TableColumn>

              <TableColumn :title="t('admin.rateLimits.window')" :width="190">
                <template #cell="{ record }">
                  <div class="rate-limit-field">
                    <InputNumber
                      v-model="form.policies[record.action][record.dimension].window_seconds"
                      :min="constraints.windowSeconds.min"
                      :max="constraints.windowSeconds.max"
                      :precision="0"
                      :error="Boolean(fieldError(record, 'window_seconds'))"
                      hide-button
                      class="w-full"
                      :aria-label="`${t(`admin.rateLimits.actions.${record.action}`)} ${t('admin.rateLimits.window')}`"
                    >
                      <template #suffix>{{ t('admin.rateLimits.seconds') }}</template>
                    </InputNumber>
                    <TypographyText
                      v-if="fieldError(record, 'window_seconds')"
                      type="danger"
                      class="rate-limit-error"
                    >
                      {{ fieldError(record, 'window_seconds') }}
                    </TypographyText>
                  </div>
                </template>
              </TableColumn>

              <TableColumn
                :title="t('admin.rateLimits.activeCounters')"
                data-index="active_counters"
                :width="140"
              />
              <TableColumn
                :title="t('admin.rateLimits.blockedRequests')"
                data-index="blocked_requests"
                :width="150"
              />
              <TableColumn :title="t('admin.rateLimits.lastBlocked')" :width="190">
                <template #cell="{ record }">
                  {{ formatDate(record.last_blocked_at) }}
                </template>
              </TableColumn>
            </template>
          </Table>
        </div>

        <Space wrap class="mt-5">
          <Button type="primary" html-type="submit" :loading="form.processing">
            {{ t('admin.rateLimits.save') }}
          </Button>
          <Tag v-if="form.recentlySuccessful" color="green">
            {{ t('admin.common.saved') }}
          </Tag>
          <TypographyText type="secondary">
            {{ t('admin.rateLimits.windowHint') }}
          </TypographyText>
        </Space>
      </form>
    </Card>
  </section>
</template>

<style scoped>
.rate-limit-stat {
  height: 100%;
  background: var(--color-fill-1);
}

.rate-limit-table-scroll {
  max-width: 100%;
  overflow-x: auto;
}

.rate-limit-table-scroll :deep(.arco-table-container) {
  overscroll-behavior-inline: contain;
}

.rate-limit-scroll-hint {
  display: none;
}

.rate-limit-field {
  display: grid;
  gap: 5px;
  min-width: 148px;
}

.rate-limit-help,
.rate-limit-error {
  display: block;
  font-size: 12px;
  line-height: 1.45;
}

@media (max-width: 575px) {
  .admin-rate-limits :deep(.arco-page-header-main) {
    display: grid;
    min-width: 0;
    gap: 6px;
  }

  .admin-rate-limits :deep(.arco-page-header-divider) {
    display: none;
  }

  .admin-rate-limits :deep(.arco-page-header-subtitle) {
    max-width: 100%;
    white-space: normal;
    line-height: 1.6;
  }

  .rate-limit-scroll-hint {
    display: block;
    margin-bottom: 10px;
    line-height: 1.6;
  }
}
</style>
