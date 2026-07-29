<script setup lang="ts">
import { computed } from 'vue'
import { Link } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  Alert,
  Button,
  Card,
  Descriptions,
  DescriptionsItem,
  Empty,
  Grid,
  GridItem,
  PageHeader,
  Space,
  Tag,
  Textarea,
  TypographyText,
} from '@mcweb/ui'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

type AuditDetail = {
  id: number
  actionLabel: string
  actionCode: string
  actor: { username: string; publicId: string } | null
  resource: {
    type: string | null
    typeLabel: string
    id: number | null
    publicId: string | null
  }
  requestId: string | null
  reason: string | null
  occurredAt: string
  occurredAtIso: string
  ipAddress: string | null
  userAgent: string | null
  beforeState: Record<string, unknown>
  afterState: Record<string, unknown>
  metadata: Record<string, unknown>
}

const props = defineProps<{
  log: AuditDetail
  backUrl: string
}>()

const { t } = useI18n()

function pretty(value: Record<string, unknown>) {
  return JSON.stringify(value, null, 2)
}

const hasBeforeState = computed(() => Object.keys(props.log.beforeState).length > 0)
const hasAfterState = computed(() => Object.keys(props.log.afterState).length > 0)
const hasMetadata = computed(() => Object.keys(props.log.metadata).length > 0)
</script>

<template>
  <section class="admin-audit-show">
    <PageHeader
      :title="log.actionLabel"
      :subtitle="t('admin.audit.detailSubtitle')"
      :show-back="false"
      class="mb-5 !px-0"
    >
      <template #extra>
        <Link :href="backUrl">
          <Button>{{ t('admin.audit.back') }}</Button>
        </Link>
      </template>
    </PageHeader>

    <Alert
      type="info"
      show-icon
      :closable="false"
      :title="t('admin.audit.immutableNotice')"
      class="mb-4"
    />

    <Card :bordered="false" class="mb-4">
      <Descriptions
        :column="{ xs: 1, sm: 2, lg: 3 }"
        bordered
        size="large"
      >
        <DescriptionsItem :label="t('admin.audit.action')">
          <Space direction="vertical" :size="2">
            <TypographyText class="font-semibold">{{ log.actionLabel }}</TypographyText>
            <TypographyText code copyable>{{ log.actionCode }}</TypographyText>
          </Space>
        </DescriptionsItem>
        <DescriptionsItem :label="t('admin.audit.actor')">
          <Space v-if="log.actor" direction="vertical" :size="2">
            <TypographyText>{{ log.actor.username }}</TypographyText>
            <TypographyText type="secondary">{{ log.actor.publicId }}</TypographyText>
          </Space>
          <TypographyText v-else type="secondary">{{ t('admin.audit.systemActor') }}</TypographyText>
        </DescriptionsItem>
        <DescriptionsItem :label="t('admin.audit.occurredAt')">
          <time :datetime="log.occurredAtIso">{{ log.occurredAt }}</time>
        </DescriptionsItem>
        <DescriptionsItem :label="t('admin.audit.resource')">
          <Space direction="vertical" :size="2">
            <TypographyText>{{ log.resource.typeLabel }}</TypographyText>
            <TypographyText type="secondary">
              {{ log.resource.publicId || log.resource.id || t('admin.audit.notAvailable') }}
            </TypographyText>
          </Space>
        </DescriptionsItem>
        <DescriptionsItem :label="t('admin.audit.requestId')">
          <Tag v-if="log.requestId" color="arcoblue" bordered>{{ log.requestId }}</Tag>
          <TypographyText v-else type="secondary">{{ t('admin.audit.notAvailable') }}</TypographyText>
        </DescriptionsItem>
        <DescriptionsItem :label="t('admin.audit.ipAddress')">
          <TypographyText>{{ log.ipAddress || t('admin.audit.notAvailable') }}</TypographyText>
        </DescriptionsItem>
        <DescriptionsItem :label="t('admin.audit.reason')" :span="3">
          <TypographyText>{{ log.reason || t('admin.audit.notAvailable') }}</TypographyText>
        </DescriptionsItem>
        <DescriptionsItem :label="t('admin.audit.userAgent')" :span="3">
          <TypographyText class="audit-wrap">
            {{ log.userAgent || t('admin.audit.notAvailable') }}
          </TypographyText>
        </DescriptionsItem>
      </Descriptions>
    </Card>

    <Grid :cols="{ xs: 1, lg: 2 }" :col-gap="16" :row-gap="16">
      <GridItem>
        <Card :bordered="false" :title="t('admin.audit.beforeState')" class="audit-state-card">
          <Textarea
            v-if="hasBeforeState"
            :model-value="pretty(log.beforeState)"
            readonly
            :auto-size="{ minRows: 8, maxRows: 20 }"
            class="audit-json"
            :aria-label="t('admin.audit.beforeState')"
          />
          <Empty v-else :description="t('admin.audit.noState')" />
        </Card>
      </GridItem>
      <GridItem>
        <Card :bordered="false" :title="t('admin.audit.afterState')" class="audit-state-card">
          <Textarea
            v-if="hasAfterState"
            :model-value="pretty(log.afterState)"
            readonly
            :auto-size="{ minRows: 8, maxRows: 20 }"
            class="audit-json"
            :aria-label="t('admin.audit.afterState')"
          />
          <Empty v-else :description="t('admin.audit.noState')" />
        </Card>
      </GridItem>
      <GridItem :span="{ xs: 1, lg: 2 }">
        <Card :bordered="false" :title="t('admin.audit.context')" class="audit-state-card">
          <Textarea
            v-if="hasMetadata"
            :model-value="pretty(log.metadata)"
            readonly
            :auto-size="{ minRows: 8, maxRows: 24 }"
            class="audit-json"
            :aria-label="t('admin.audit.context')"
          />
          <Empty v-else :description="t('admin.audit.noContext')" />
        </Card>
      </GridItem>
    </Grid>
  </section>
</template>

<style scoped>
.audit-wrap {
  overflow-wrap: anywhere;
}

.audit-json :deep(textarea) {
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  line-height: 1.55;
}
</style>
