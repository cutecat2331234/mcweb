<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, reactive, ref } from 'vue'
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  Alert,
  Button,
  Card,
  Descriptions,
  DescriptionsItem,
  Drawer,
  Empty,
  Form,
  FormItem,
  Grid,
  GridItem,
  Input,
  InputSearch,
  InputNumber,
  List,
  ListItem,
  Message,
  Modal,
  PageHeader,
  Select,
  Space,
  Statistic,
  Table,
  TableColumn,
  Tag,
  Textarea,
  Timeline,
  TimelineItem,
  TypographyText,
} from '@mcweb/ui'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { postJson, HttpError } from '@/lib/http'

defineOptions({ layout: AdminLayout })

type Movement = {
  id: string
  type: string
  quantity: number
  available_delta: number
  reserved_delta: number
  sold_delta: number
  available_after: number | null
  reserved_after: number
  sold_after: number
  reason?: string | null
  created_at: string
}

type Target = {
  id: string
  target_type: 'product' | 'variant'
  target_id: string
  name: string
  sku?: string | null
  available: number
  reserved: number
  sold: number
  anomalies: string[]
  movements: Movement[]
}

type ReservationAnomaly = {
  id: number
  order_id: string
  order_number: string
  target_id: string
  quantity: number
  status: string
  expires_at: string
  anomaly: string
}

type Authorization = {
  authorization_token: string
  confirmation: string
  request_id: string
  expires_in: number
  preview: {
    target: string
    before: number
    delta: number
    after: number
  }
}

type HealthFilter = 'all' | 'healthy' | 'anomaly'

const props = defineProps<{
  summary: {
    targets: number
    available: number
    reserved: number
    sold: number
    anomalies: number
  }
  targets: Target[]
  expired_reservations: ReservationAnomaly[]
  mismatched_reservations: ReservationAnomaly[]
  permissions: {
    adjust: boolean
    recover: boolean
  }
  paths: {
    authorize: string
    adjust: string
  }
}>()

const { t, locale } = useI18n()
const selectedTarget = ref<Target | null>(null)
const adjustmentTarget = ref<Target | null>(null)
const authorization = ref<Authorization | null>(null)
const submitting = ref(false)
const resultBalance = ref<number | null>(null)
const searchQuery = ref('')
const healthFilter = ref<HealthFilter>('all')
const isMobile = ref(false)
let viewportQuery: MediaQueryList | null = null
const adjustment = reactive({
  delta: 0,
  reason: '',
  request_id: '',
  confirmation: '',
})

const adjustmentVisible = computed({
  get: () => adjustmentTarget.value !== null,
  set: (visible: boolean) => {
    if (!visible) closeAdjustment()
  },
})

const anomalies = computed(() => [
  ...props.expired_reservations,
  ...props.mismatched_reservations,
])

const healthOptions = computed(() => [
  { label: t('admin.inventory.stockTable'), value: 'all' },
  { label: t('admin.inventory.healthy'), value: 'healthy' },
  { label: t('admin.inventory.metrics.anomalies'), value: 'anomaly' },
])

const filteredTargets = computed(() => {
  const query = searchQuery.value.trim().toLocaleLowerCase(locale.value)

  return props.targets.filter((target) => {
    const matchesQuery = !query || [target.name, target.sku]
      .filter((value): value is string => Boolean(value))
      .some((value) => value.toLocaleLowerCase(locale.value).includes(query))
    const matchesHealth = healthFilter.value === 'all'
      || (healthFilter.value === 'healthy' && target.anomalies.length === 0)
      || (healthFilter.value === 'anomaly' && target.anomalies.length > 0)

    return matchesQuery && matchesHealth
  })
})

function syncViewport(event?: MediaQueryListEvent) {
  isMobile.value = event?.matches ?? viewportQuery?.matches ?? false
}

onMounted(() => {
  viewportQuery = window.matchMedia('(max-width: 767px)')
  syncViewport()
  viewportQuery.addEventListener('change', syncViewport)
})

onBeforeUnmount(() => {
  viewportQuery?.removeEventListener('change', syncViewport)
})

function formatDate(value: string) {
  return new Intl.DateTimeFormat(locale.value, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value))
}

function signedNumber(value: number) {
  return value > 0 ? `+${value}` : `${value}`
}

function anomalyColor(target: Target) {
  if (target.anomalies.includes('negative_stock')) return 'red'
  if (target.anomalies.length) return 'orange'
  return 'green'
}

function openAdjustment(target: Target) {
  adjustmentTarget.value = target
  authorization.value = null
  resultBalance.value = null
  adjustment.delta = 0
  adjustment.reason = ''
  adjustment.request_id = crypto.randomUUID()
  adjustment.confirmation = ''
}

function closeAdjustment() {
  if (submitting.value) return
  adjustmentTarget.value = null
  authorization.value = null
  resultBalance.value = null
}

function payload() {
  if (!adjustmentTarget.value) return null
  return {
    adjustment: {
      target_type: adjustmentTarget.value.target_type,
      target_id: adjustmentTarget.value.target_id,
      delta: adjustment.delta,
      request_id: adjustment.request_id,
      reason: adjustment.reason,
      authorization_token: authorization.value?.authorization_token,
      confirmation: adjustment.confirmation,
    },
  }
}

function errorMessage(error: unknown) {
  if (error instanceof HttpError && error.body && typeof error.body === 'object' && 'error' in error.body) {
    return String((error.body as { error: unknown }).error)
  }
  return t('admin.inventory.operationFailed')
}

async function authorizeAdjustment() {
  const body = payload()
  if (!body) return
  submitting.value = true
  try {
    authorization.value = await postJson<Authorization>(props.paths.authorize, body)
    adjustment.confirmation = ''
  } catch (error) {
    Message.error(errorMessage(error))
  } finally {
    submitting.value = false
  }
}

async function executeAdjustment() {
  const body = payload()
  if (!body) return
  submitting.value = true
  try {
    const response = await postJson<{ balance: number }>(props.paths.adjust, body)
    resultBalance.value = response.balance
    Message.success(t('admin.inventory.adjustmentSucceeded'))
    router.reload({
      only: ['summary', 'targets', 'expired_reservations', 'mismatched_reservations'],
      preserveScroll: true,
    })
  } catch (error) {
    Message.error(errorMessage(error))
  } finally {
    submitting.value = false
  }
}
</script>

<template>
  <Space direction="vertical" :size="24" fill>
    <PageHeader
      :title="t('admin.inventory.title')"
      :subtitle="t('admin.inventory.subtitle')"
      :show-back="false"
    />

    <Alert
      v-if="summary.anomalies > 0"
      type="warning"
      :title="t('admin.inventory.anomalyAlertTitle', { count: summary.anomalies })"
    >
      {{ t('admin.inventory.anomalyAlertDescription') }}
    </Alert>

    <Grid :cols="{ xs: 1, sm: 2, lg: 5 }" :col-gap="16" :row-gap="16">
      <GridItem>
        <Card :bordered="false">
          <Statistic :title="t('admin.inventory.metrics.targets')" :value="summary.targets" />
        </Card>
      </GridItem>
      <GridItem>
        <Card :bordered="false">
          <Statistic :title="t('admin.inventory.metrics.available')" :value="summary.available" />
        </Card>
      </GridItem>
      <GridItem>
        <Card :bordered="false">
          <Statistic :title="t('admin.inventory.metrics.reserved')" :value="summary.reserved" />
        </Card>
      </GridItem>
      <GridItem>
        <Card :bordered="false">
          <Statistic :title="t('admin.inventory.metrics.sold')" :value="summary.sold" />
        </Card>
      </GridItem>
      <GridItem>
        <Card :bordered="false">
          <Statistic :title="t('admin.inventory.metrics.anomalies')" :value="summary.anomalies" />
        </Card>
      </GridItem>
    </Grid>

    <Card :title="t('admin.inventory.stockTable')" :bordered="false">
      <Grid :cols="{ xs: 1, md: 2 }" :col-gap="12" :row-gap="12">
        <GridItem>
          <InputSearch
            v-model="searchQuery"
            allow-clear
            :placeholder="t('nav.search')"
          />
        </GridItem>
        <GridItem>
          <Select
            v-model="healthFilter"
            :options="healthOptions"
          />
        </GridItem>
      </Grid>

      <Empty
        v-if="filteredTargets.length === 0"
        :description="t('common.pagination.noResults')"
      />
      <Table
        v-else-if="!isMobile"
        :data="filteredTargets"
        :pagination="false"
        row-key="id"
        size="small"
        :bordered="{ cell: true }"
        :scroll="{ x: 980 }"
        stripe
        @row-click="(record: Target) => (selectedTarget = record)"
      >
        <TableColumn :title="t('admin.inventory.columns.item')" data-index="name" :width="260">
          <template #cell="{ record }">
            <Space direction="vertical" size="mini">
              <TypographyText bold>{{ record.name }}</TypographyText>
              <TypographyText v-if="record.sku" type="secondary">{{ record.sku }}</TypographyText>
            </Space>
          </template>
        </TableColumn>
        <TableColumn :title="t('admin.inventory.columns.available')" data-index="available" :width="120" />
        <TableColumn :title="t('admin.inventory.columns.reserved')" data-index="reserved" :width="120" />
        <TableColumn :title="t('admin.inventory.columns.sold')" data-index="sold" :width="120" />
        <TableColumn :title="t('admin.inventory.columns.health')" :width="180">
          <template #cell="{ record }">
            <Tag :color="anomalyColor(record)">
              {{
                record.anomalies.length
                  ? t('admin.inventory.anomalyCount', { count: record.anomalies.length })
                  : t('admin.inventory.healthy')
              }}
            </Tag>
          </template>
        </TableColumn>
        <TableColumn :title="t('admin.inventory.columns.actions')" :width="190" fixed="right">
          <template #cell="{ record }">
            <Space>
              <Button size="small" @click.stop="selectedTarget = record">
                {{ t('admin.inventory.viewLedger') }}
              </Button>
              <Button
                v-if="permissions.adjust"
                size="small"
                type="primary"
                @click.stop="openAdjustment(record)"
              >
                {{ t('admin.inventory.adjust') }}
              </Button>
            </Space>
          </template>
        </TableColumn>
      </Table>

      <List v-else :bordered="false" size="small">
        <ListItem v-for="target in filteredTargets" :key="target.id">
          <Space direction="vertical" :size="12" fill>
            <Space align="center" wrap>
              <TypographyText bold>{{ target.name }}</TypographyText>
              <TypographyText v-if="target.sku" type="secondary">{{ target.sku }}</TypographyText>
              <Tag :color="anomalyColor(target)">
                {{
                  target.anomalies.length
                    ? t('admin.inventory.anomalyCount', { count: target.anomalies.length })
                    : t('admin.inventory.healthy')
                }}
              </Tag>
            </Space>

            <Descriptions :column="1" bordered size="small">
              <DescriptionsItem :label="t('admin.inventory.columns.available')">
                {{ target.available }}
              </DescriptionsItem>
              <DescriptionsItem :label="t('admin.inventory.columns.reserved')">
                {{ target.reserved }}
              </DescriptionsItem>
              <DescriptionsItem :label="t('admin.inventory.columns.sold')">
                {{ target.sold }}
              </DescriptionsItem>
            </Descriptions>

            <Grid :cols="permissions.adjust ? 2 : 1" :col-gap="8">
              <GridItem>
                <Button long @click="selectedTarget = target">
                  {{ t('admin.inventory.viewLedger') }}
                </Button>
              </GridItem>
              <GridItem v-if="permissions.adjust">
                <Button type="primary" long @click="openAdjustment(target)">
                  {{ t('admin.inventory.adjust') }}
                </Button>
              </GridItem>
            </Grid>
          </Space>
        </ListItem>
      </List>
    </Card>

    <Card :title="t('admin.inventory.anomalyQueue')" :bordered="false">
      <Empty v-if="anomalies.length === 0" :description="t('admin.inventory.noAnomalies')" />
      <Table
        v-else-if="!isMobile"
        :data="anomalies"
        :pagination="false"
        row-key="id"
        size="small"
        :bordered="{ cell: true }"
        :scroll="{ x: 760 }"
        stripe
      >
        <TableColumn :title="t('admin.inventory.columns.order')" data-index="order_number" />
        <TableColumn :title="t('admin.inventory.columns.quantity')" data-index="quantity" />
        <TableColumn :title="t('admin.inventory.columns.expiresAt')">
          <template #cell="{ record }">{{ formatDate(record.expires_at) }}</template>
        </TableColumn>
        <TableColumn :title="t('admin.inventory.columns.health')">
          <template #cell="{ record }">
            <Tag color="orange">{{ t(`admin.inventory.anomalies.${record.anomaly}`) }}</Tag>
          </template>
        </TableColumn>
      </Table>

      <List v-else :bordered="false" size="small">
        <ListItem v-for="anomaly in anomalies" :key="anomaly.id">
          <Space direction="vertical" :size="12" fill>
            <Space align="center" wrap>
              <TypographyText bold>{{ anomaly.order_number }}</TypographyText>
              <Tag color="orange">{{ t(`admin.inventory.anomalies.${anomaly.anomaly}`) }}</Tag>
            </Space>
            <Descriptions :column="1" bordered size="small">
              <DescriptionsItem :label="t('admin.inventory.columns.quantity')">
                {{ anomaly.quantity }}
              </DescriptionsItem>
              <DescriptionsItem :label="t('admin.inventory.columns.expiresAt')">
                {{ formatDate(anomaly.expires_at) }}
              </DescriptionsItem>
            </Descriptions>
          </Space>
        </ListItem>
      </List>
    </Card>
  </Space>

  <Drawer
    :visible="Boolean(selectedTarget)"
    :width="'min(620px, calc(100vw - 24px))'"
    :title="t('admin.inventory.ledgerTitle')"
    unmount-on-close
    @cancel="selectedTarget = null"
  >
    <template v-if="selectedTarget">
      <Space direction="vertical" :size="20" fill>
        <Descriptions :column="1" bordered size="small">
          <DescriptionsItem :label="t('admin.inventory.columns.item')">{{ selectedTarget.name }}</DescriptionsItem>
          <DescriptionsItem :label="t('admin.inventory.columns.available')">{{ selectedTarget.available }}</DescriptionsItem>
          <DescriptionsItem :label="t('admin.inventory.columns.reserved')">{{ selectedTarget.reserved }}</DescriptionsItem>
          <DescriptionsItem :label="t('admin.inventory.columns.sold')">{{ selectedTarget.sold }}</DescriptionsItem>
        </Descriptions>

        <Empty
          v-if="selectedTarget.movements.length === 0"
          :description="t('admin.inventory.noMovements')"
        />
        <Timeline v-else>
          <TimelineItem v-for="movement in selectedTarget.movements" :key="movement.id">
            <Space direction="vertical" size="mini">
              <TypographyText bold>{{ t(`admin.inventory.movements.${movement.type}`) }}</TypographyText>
              <TypographyText type="secondary">{{ formatDate(movement.created_at) }}</TypographyText>
              <TypographyText>
                {{
                  t('admin.inventory.movementDeltas', {
                    available: signedNumber(movement.available_delta),
                    reserved: signedNumber(movement.reserved_delta),
                    sold: signedNumber(movement.sold_delta),
                  })
                }}
              </TypographyText>
              <TypographyText v-if="movement.reason">{{ movement.reason }}</TypographyText>
            </Space>
          </TimelineItem>
        </Timeline>
      </Space>
    </template>
  </Drawer>

  <Modal
    v-model:visible="adjustmentVisible"
    :title="t('admin.inventory.adjustmentTitle')"
    :ok-text="authorization ? t('admin.inventory.executeAdjustment') : t('admin.inventory.previewAdjustment')"
    :cancel-text="t('common.cancel')"
    :ok-loading="submitting"
    :mask-closable="false"
    :closable="!submitting"
    unmount-on-close
    @ok="authorization ? executeAdjustment() : authorizeAdjustment()"
  >
    <template v-if="adjustmentTarget">
      <Space direction="vertical" :size="16" fill>
        <Alert type="warning" :title="t('admin.inventory.adjustmentRiskTitle')">
          {{ t('admin.inventory.adjustmentRiskDescription') }}
        </Alert>

        <Form layout="vertical">
          <FormItem :label="t('admin.inventory.columns.item')">
            <Input :model-value="adjustmentTarget.name" readonly />
          </FormItem>
          <FormItem :label="t('admin.inventory.adjustmentDelta')" required>
            <InputNumber
              v-model="adjustment.delta"
              :min="-1000000"
              :max="1000000"
              :disabled="Boolean(authorization)"
              long
            />
          </FormItem>
          <FormItem :label="t('admin.inventory.adjustmentReason')" required>
            <Textarea
              v-model="adjustment.reason"
              :max-length="1000"
              show-word-limit
              :disabled="Boolean(authorization)"
            />
          </FormItem>

          <Descriptions v-if="authorization" :column="1" bordered size="small">
            <DescriptionsItem :label="t('admin.inventory.before')">{{ authorization.preview.before }}</DescriptionsItem>
            <DescriptionsItem :label="t('admin.inventory.adjustmentDelta')">
              {{ signedNumber(authorization.preview.delta) }}
            </DescriptionsItem>
            <DescriptionsItem :label="t('admin.inventory.after')">{{ authorization.preview.after }}</DescriptionsItem>
          </Descriptions>

          <FormItem
            v-if="authorization"
            :label="t('admin.inventory.confirmationLabel', { confirmation: authorization.confirmation })"
            required
          >
            <Input v-model="adjustment.confirmation" autocomplete="off" />
          </FormItem>

          <Alert v-if="resultBalance !== null" type="success">
            {{ t('admin.inventory.resultBalance', { balance: resultBalance }) }}
          </Alert>
        </Form>
      </Space>
    </template>
  </Modal>
</template>
