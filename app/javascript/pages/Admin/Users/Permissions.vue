<script setup lang="ts">
import { computed, ref } from 'vue'
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
  Grid,
  GridItem,
  InputSearch,
  Option,
  PageHeader,
  Select,
  Space,
  Statistic,
  Table,
  TableColumn,
  Tag,
  TypographyText,
} from '@mcweb/ui'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

type Source = {
  type: 'account' | 'role' | 'group'
  id?: number
  name: string
  primary?: boolean
}

type PermissionDecision = {
  key: string
  name: string
  description: string
  allowed: boolean
  eligible: boolean
  reason: string
  sources: Source[]
}

type PermissionRow = PermissionDecision & {
  categoryKey: string
  categoryName: string
}

const props = defineProps<{
  user: {
    public_id: string
    username: string
    display_name: string | null
    status: string
    account_type: string
    eligible: boolean
    permission_version: number
  }
  summary: {
    total: number
    allowed: number
    denied: number
  }
  categories: Array<{
    key: string
    name: string
    permissions: PermissionDecision[]
  }>
  backUrl: string
}>()

const { t } = useI18n()
const search = ref('')
const outcome = ref<'all' | 'allowed' | 'denied'>('all')
const selected = ref<PermissionRow | null>(null)
const drawerOpen = computed({
  get: () => selected.value !== null,
  set: (open: boolean) => {
    if (!open) selected.value = null
  },
})

const rows = computed<PermissionRow[]>(() => props.categories.flatMap(category =>
  category.permissions.map(permission => ({
    ...permission,
    categoryKey: category.key,
    categoryName: category.name,
  })),
))

const filteredRows = computed(() => {
  const query = search.value.trim().toLocaleLowerCase()
  return rows.value.filter((row) => {
    if (outcome.value === 'allowed' && !row.allowed) return false
    if (outcome.value === 'denied' && row.allowed) return false
    if (!query) return true

    return [
      row.name,
      row.description,
      row.categoryName,
      ...row.sources.map(source => source.name),
    ].some(value => value.toLocaleLowerCase().includes(query))
  })
})

function sourceLabel(source: Source) {
  return `${t(`admin.permissionExplanation.sourceTypes.${source.type}`)} · ${source.name}`
}
</script>

<template>
  <Space direction="vertical" :size="16" fill>
    <PageHeader
      :title="t('admin.permissionExplanation.title')"
      :subtitle="t('admin.permissionExplanation.subtitle')"
      :show-back="false"
    >
      <template #extra>
        <Button @click="router.visit(backUrl)">
          {{ t('admin.permissionExplanation.back') }}
        </Button>
      </template>
    </PageHeader>

    <Alert
      type="info"
      show-icon
      :closable="false"
      :title="t('admin.permissionExplanation.memberViewNotice')"
    />
    <Alert
      v-if="!user.eligible"
      type="warning"
      show-icon
      :closable="false"
      :title="t('admin.permissionExplanation.ineligibleNotice')"
    />

    <Card :bordered="false">
      <Descriptions :column="{ xs: 1, sm: 2, lg: 4 }" bordered>
        <DescriptionsItem :label="t('admin.permissionExplanation.member')">
          <Space direction="vertical" :size="0">
            <TypographyText bold>
              {{ user.display_name || user.username }}
            </TypographyText>
            <TypographyText type="secondary">{{ user.username }}</TypographyText>
          </Space>
        </DescriptionsItem>
        <DescriptionsItem :label="t('admin.permissionExplanation.accountStatus')">
          <Tag :color="user.eligible ? 'green' : 'red'">
            {{ t(`admin.permissionExplanation.statuses.${user.status}`) }}
          </Tag>
        </DescriptionsItem>
        <DescriptionsItem :label="t('admin.permissionExplanation.accountType')">
          {{ t(`admin.permissionExplanation.accountTypes.${user.account_type}`) }}
        </DescriptionsItem>
        <DescriptionsItem :label="t('admin.permissionExplanation.version')">
          <Tag color="arcoblue" bordered>v{{ user.permission_version }}</Tag>
        </DescriptionsItem>
      </Descriptions>
    </Card>

    <Grid :cols="{ xs: 1, sm: 3 }" :col-gap="16" :row-gap="16">
      <GridItem>
        <Card :bordered="false">
          <Statistic :title="t('admin.permissionExplanation.total')" :value="summary.total" />
        </Card>
      </GridItem>
      <GridItem>
        <Card :bordered="false">
          <Statistic
            :title="t('admin.permissionExplanation.allowed')"
            :value="summary.allowed"
          />
        </Card>
      </GridItem>
      <GridItem>
        <Card :bordered="false">
          <Statistic
            :title="t('admin.permissionExplanation.denied')"
            :value="summary.denied"
          />
        </Card>
      </GridItem>
    </Grid>

    <Card :bordered="false">
      <Space direction="vertical" :size="16" fill>
      <Grid :cols="24" :col-gap="12" :row-gap="12">
        <GridItem :span="{ xs: 24, sm: 16, lg: 18 }">
          <InputSearch
            v-model="search"
            allow-clear
            :placeholder="t('admin.permissionExplanation.searchPlaceholder')"
            :aria-label="t('admin.permissionExplanation.search')"
          />
        </GridItem>
        <GridItem :span="{ xs: 24, sm: 8, lg: 6 }">
          <Select
            v-model="outcome"
            :aria-label="t('admin.permissionExplanation.outcome')"
          >
            <Option value="all">{{ t('admin.permissionExplanation.all') }}</Option>
            <Option value="allowed">{{ t('admin.permissionExplanation.allowedOnly') }}</Option>
            <Option value="denied">{{ t('admin.permissionExplanation.deniedOnly') }}</Option>
          </Select>
        </GridItem>
      </Grid>

      <Empty
        v-if="filteredRows.length === 0"
        :description="t('admin.permissionExplanation.empty')"
      />
      <Table
        v-else
        :data="filteredRows"
        :pagination="{ pageSize: 50, showTotal: true }"
        :bordered="{ wrapper: true }"
        :scroll="{ minWidth: 900 }"
        row-key="key"
      >
          <template #columns>
            <TableColumn
              :title="t('admin.permissionExplanation.category')"
              data-index="categoryName"
              :width="150"
            />
            <TableColumn :title="t('admin.permissionExplanation.permission')" :width="300">
              <template #cell="{ record }">
                <Space direction="vertical" :size="2">
                  <TypographyText bold>{{ record.name }}</TypographyText>
                  <TypographyText type="secondary">{{ record.description }}</TypographyText>
                </Space>
              </template>
            </TableColumn>
            <TableColumn :title="t('admin.permissionExplanation.decision')" :width="120">
              <template #cell="{ record }">
                <Tag :color="record.allowed ? 'green' : 'red'">
                  {{ t(record.allowed
                    ? 'admin.permissionExplanation.allowed'
                    : 'admin.permissionExplanation.denied') }}
                </Tag>
              </template>
            </TableColumn>
            <TableColumn :title="t('admin.permissionExplanation.source')" :width="250">
              <template #cell="{ record }">
                <Space v-if="record.sources.length" wrap :size="[4, 4]">
                  <Tag
                    v-for="source in record.sources.slice(0, 2)"
                    :key="`${source.type}-${source.id || source.name}`"
                    bordered
                  >
                    {{ sourceLabel(source) }}
                  </Tag>
                  <Tag v-if="record.sources.length > 2" bordered>
                    +{{ record.sources.length - 2 }}
                  </Tag>
                </Space>
                <TypographyText v-else type="secondary">
                  {{ t('admin.permissionExplanation.noSource') }}
                </TypographyText>
              </template>
            </TableColumn>
            <TableColumn :title="t('admin.permissionExplanation.details')" :width="140" fixed="right">
              <template #cell="{ record }">
                <Button
                  type="text"
                  :aria-label="`${t('admin.permissionExplanation.viewDetails')}: ${record.name}`"
                  @click="selected = record"
                >
                  {{ t('admin.permissionExplanation.viewDetails') }}
                </Button>
              </template>
            </TableColumn>
          </template>
      </Table>
      </Space>
    </Card>

    <Drawer
      v-model:visible="drawerOpen"
      :title="selected?.name || t('admin.permissionExplanation.details')"
      :width="'min(560px, calc(100vw - 32px))'"
      :footer="false"
      unmount-on-close
    >
      <Space v-if="selected" direction="vertical" :size="12" fill>
        <Descriptions :column="1" bordered>
          <DescriptionsItem :label="t('admin.permissionExplanation.decision')">
            <Tag :color="selected.allowed ? 'green' : 'red'">
              {{ t(selected.allowed
                ? 'admin.permissionExplanation.allowed'
                : 'admin.permissionExplanation.denied') }}
            </Tag>
          </DescriptionsItem>
          <DescriptionsItem :label="t('admin.permissionExplanation.reason')">
            {{ t(`admin.permissionExplanation.reasons.${selected.reason}`) }}
          </DescriptionsItem>
          <DescriptionsItem :label="t('admin.permissionExplanation.description')">
            {{ selected.description }}
          </DescriptionsItem>
        </Descriptions>

        <Card
          v-for="source in selected.sources"
          :key="`${source.type}-${source.id || source.name}`"
          :bordered="true"
        >
          <Space direction="vertical" :size="4">
            <Tag bordered>{{ t(`admin.permissionExplanation.sourceTypes.${source.type}`) }}</Tag>
            <TypographyText bold>{{ source.name }}</TypographyText>
            <TypographyText v-if="source.type === 'group'" type="secondary">
              {{ t('admin.permissionExplanation.primaryGroup') }}:
              {{ t(source.primary
                ? 'admin.permissionExplanation.yes'
                : 'admin.permissionExplanation.no') }}
            </TypographyText>
          </Space>
        </Card>
        <Empty
          v-if="selected.sources.length === 0"
          :description="t('admin.permissionExplanation.noSource')"
        />
      </Space>
    </Drawer>
  </Space>
</template>
