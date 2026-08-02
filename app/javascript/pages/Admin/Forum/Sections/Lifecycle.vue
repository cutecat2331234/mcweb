<script setup lang="ts">
import { router, useForm } from '@inertiajs/vue3'
import { computed, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

const { t, locale } = useI18n()

type Impact = {
  sections: number
  descendants: number
  topics: number
  posts: number
  moderation_cases: number
  active_moderation_cases: number
  moderators: number
  subscriptions: number
  member_mutes: number
  moderation_mutes: number
}

type MigrationTarget = {
  id: number
  name: string
  category: string | null
}

const props = defineProps<{
  title: string
  section: {
    id: number
    name: string
    slug: string
    archived: boolean
    self_archived: boolean
    inherited_archived: boolean
    effectively_active: boolean
    lifecycle_status: 'effectively_active' | 'self_archived' | 'inherited_archived'
    archived_ancestor: {
      id: number
      name: string
      slug: string
      lifecycle_url: string
    } | null
    archived_at: string | null
    archived_by: string | null
    archived_reason: string | null
  }
  impact: Impact
  destroyBlockers: string[]
  archiveUrl: string
  restoreUrl: string
  destroyUrl: string
  migrateTopicsUrl: string
  migrationTargets: MigrationTarget[]
  canManageLifecycle: boolean
  canMigrateTopics: boolean
  canDelete: boolean
  confirmations: {
    archive: string
    restore: string
    destroy: string
  }
  backUrl: string
}>()

const impactDrawerVisible = ref(false)
const lifecycleModalVisible = ref(false)
const migrationModalVisible = ref(false)
const destroyModalVisible = ref(false)

const lifecycleForm = useForm({ reason: '', confirmation: '' })
const migrationForm = useForm<{ target_section_id: number | null; reason: string }>({
  target_section_id: null,
  reason: '',
})
const destroyForm = useForm({ reason: '', confirmation: '' })

const lifecycleOperation = computed(() => (props.section.self_archived ? 'restore' : 'archive'))
const lifecycleUrl = computed(() => (
  props.section.self_archived ? props.restoreUrl : props.archiveUrl
))
const lifecycleConfirmation = computed(() => props.confirmations[lifecycleOperation.value])
const lifecycleReady = computed(() => (
  lifecycleForm.reason.trim().length > 0
  && lifecycleForm.confirmation === lifecycleConfirmation.value
  && !lifecycleForm.processing
))
const migrationReady = computed(() => (
  props.canMigrateTopics
  && props.impact.topics > 0
  && migrationForm.target_section_id !== null
  && migrationForm.reason.trim().length > 0
  && !migrationForm.processing
))
const destroyReady = computed(() => (
  props.canDelete
  && props.destroyBlockers.length === 0
  && destroyForm.reason.trim().length > 0
  && destroyForm.confirmation === props.confirmations.destroy
  && !destroyForm.processing
))

const impactEntries = computed(() => [
  { key: 'sections', label: t('admin.forms.section.lifecycleImpactSections'), value: props.impact.sections },
  { key: 'descendants', label: t('admin.forms.section.lifecycleImpactDescendants'), value: props.impact.descendants },
  { key: 'topics', label: t('admin.forms.section.lifecycleImpactTopics'), value: props.impact.topics },
  { key: 'posts', label: t('admin.forms.section.lifecycleImpactPosts'), value: props.impact.posts },
  { key: 'moderationCases', label: t('admin.forms.section.lifecycleImpactCases'), value: props.impact.moderation_cases },
  { key: 'activeCases', label: t('admin.forms.section.lifecycleImpactActiveCases'), value: props.impact.active_moderation_cases },
  { key: 'moderators', label: t('admin.forms.section.lifecycleImpactModerators'), value: props.impact.moderators },
  { key: 'subscriptions', label: t('admin.forms.section.lifecycleImpactSubscriptions'), value: props.impact.subscriptions },
  { key: 'memberMutes', label: t('admin.forms.section.lifecycleImpactMemberMutes'), value: props.impact.member_mutes },
  { key: 'moderationMutes', label: t('admin.forms.section.lifecycleImpactModerationMutes'), value: props.impact.moderation_mutes },
])

const headlineImpact = computed(() => impactEntries.value.slice(0, 4))

const statusPresentation = computed(() => {
  if (props.section.self_archived) {
    return {
      color: 'orange',
      alert: 'warning' as const,
      label: t('admin.forms.section.lifecycleSelfArchived'),
      notice: t('admin.forms.section.lifecycleSelfArchivedNotice'),
    }
  }
  if (props.section.inherited_archived) {
    return {
      color: 'orangered',
      alert: 'warning' as const,
      label: t('admin.forms.section.lifecycleInheritedArchived'),
      notice: t('admin.forms.section.lifecycleInheritedArchivedNotice', {
        ancestor: props.section.archived_ancestor?.name || '',
      }),
    }
  }
  return {
    color: 'green',
    alert: 'success' as const,
    label: t('admin.forms.section.lifecycleEffectivelyActive'),
    notice: t('admin.forms.section.lifecycleActiveNotice'),
  }
})

function formattedArchivedAt() {
  if (!props.section.archived_at) return t('common.notAvailable')
  return new Intl.DateTimeFormat(locale.value, { dateStyle: 'medium', timeStyle: 'short' })
    .format(new Date(props.section.archived_at))
}

function responseHasAlert(page: { props: Record<string, unknown> }) {
  const flash = page.props.flash as { alert?: string | null } | undefined
  return Boolean(flash?.alert)
}

function submitLifecycle() {
  if (!lifecycleReady.value) return
  lifecycleForm.patch(lifecycleUrl.value, {
    preserveScroll: true,
    onSuccess: (page) => {
      if (responseHasAlert(page)) return
      lifecycleModalVisible.value = false
      lifecycleForm.reset()
    },
  })
}

function migrateTopics() {
  if (!migrationReady.value) return
  migrationForm.patch(props.migrateTopicsUrl, {
    preserveScroll: true,
    onSuccess: (page) => {
      if (responseHasAlert(page)) return
      migrationModalVisible.value = false
      migrationForm.reset()
    },
  })
}

function destroySection() {
  if (!destroyReady.value) return
  destroyForm.delete(props.destroyUrl, { preserveScroll: true })
}
</script>

<template>
  <a-space direction="vertical" :size="16" fill>
    <a-page-header :title="title" :subtitle="section.slug" @back="router.visit(backUrl)">
      <template #extra>
        <a-space wrap>
          <a-tag :color="statusPresentation.color" size="large">
            {{ statusPresentation.label }}
          </a-tag>
          <a-button type="outline" @click="impactDrawerVisible = true">
            {{ t('admin.forms.section.lifecycleViewImpact') }}
          </a-button>
        </a-space>
      </template>
    </a-page-header>

    <a-alert :type="statusPresentation.alert" :title="statusPresentation.notice" show-icon>
      <template v-if="section.inherited_archived && section.archived_ancestor" #action>
        <a-button
          type="text"
          size="small"
          @click="router.visit(section.archived_ancestor.lifecycle_url)"
        >
          {{ t('admin.forms.section.lifecycleOpenAncestor') }}
        </a-button>
      </template>
    </a-alert>

    <a-card :bordered="true">
      <a-grid :cols="{ xs: 2, sm: 4 }" :col-gap="12" :row-gap="12">
        <a-grid-item v-for="entry in headlineImpact" :key="entry.key">
          <a-statistic :title="entry.label" :value="entry.value" />
        </a-grid-item>
      </a-grid>
      <a-divider />
      <a-space wrap>
        <a-button
          v-if="canManageLifecycle"
          :type="section.self_archived ? 'primary' : 'outline'"
          :status="section.self_archived ? 'success' : 'warning'"
          @click="lifecycleModalVisible = true"
        >
          {{ section.self_archived
            ? t('admin.forms.section.lifecycleRestoreAction')
            : t('admin.forms.section.lifecycleArchiveAction') }}
        </a-button>
        <a-button
          v-if="canMigrateTopics && impact.topics > 0"
          type="primary"
          :disabled="migrationTargets.length === 0"
          @click="migrationModalVisible = true"
        >
          {{ t('admin.forms.section.lifecycleMigrateAction') }}
        </a-button>
        <a-button
          v-if="canDelete"
          status="danger"
          @click="destroyModalVisible = true"
        >
          {{ t('admin.forms.section.lifecycleDeleteAction') }}
        </a-button>
      </a-space>
    </a-card>

    <a-card
      v-if="section.self_archived"
      :title="t('admin.forms.section.lifecycleArchiveRecord')"
      :bordered="true"
    >
      <a-descriptions :column="{ xs: 1, md: 3 }" bordered size="small">
        <a-descriptions-item :label="t('admin.forms.section.lifecycleArchivedAt')">
          {{ formattedArchivedAt() }}
        </a-descriptions-item>
        <a-descriptions-item :label="t('admin.forms.section.lifecycleArchivedBy')">
          {{ section.archived_by || t('common.notAvailable') }}
        </a-descriptions-item>
        <a-descriptions-item :label="t('admin.forms.section.lifecycleReason')">
          {{ section.archived_reason || t('common.notAvailable') }}
        </a-descriptions-item>
      </a-descriptions>
    </a-card>

    <a-drawer
      v-model:visible="impactDrawerVisible"
      :title="t('admin.forms.section.lifecycleImpactTitle')"
      :width="520"
      :footer="false"
      unmount-on-close
    >
      <a-grid :cols="{ xs: 1, sm: 2 }" :col-gap="12" :row-gap="12">
        <a-grid-item v-for="entry in impactEntries" :key="entry.key">
          <a-card size="small" :bordered="true">
            <a-statistic :title="entry.label" :value="entry.value" />
          </a-card>
        </a-grid-item>
      </a-grid>
    </a-drawer>

    <a-modal
      v-model:visible="lifecycleModalVisible"
      :title="section.self_archived
        ? t('admin.forms.section.lifecycleRestoreTitle')
        : t('admin.forms.section.lifecycleArchiveTitle')"
      :ok-text="section.self_archived
        ? t('admin.forms.section.lifecycleRestoreAction')
        : t('admin.forms.section.lifecycleArchiveAction')"
      :ok-button-props="{ disabled: !lifecycleReady, loading: lifecycleForm.processing }"
      :mask-closable="!lifecycleForm.processing"
      :closable="!lifecycleForm.processing"
      unmount-on-close
      @ok="submitLifecycle"
    >
      <a-space direction="vertical" :size="16" fill>
        <a-alert
          :type="section.self_archived ? 'success' : 'warning'"
          :title="section.self_archived
            ? t('admin.forms.section.lifecycleRestoreHelp')
            : t('admin.forms.section.lifecycleArchiveHelp')"
          show-icon
        />
        <a-form layout="vertical">
          <a-form-item :label="t('admin.forms.section.lifecycleReason')" required>
            <a-textarea
              v-model="lifecycleForm.reason"
              :max-length="1000"
              show-word-limit
              :auto-size="{ minRows: 3, maxRows: 6 }"
              :placeholder="t('admin.forms.section.lifecycleReasonPlaceholder')"
            />
          </a-form-item>
          <a-form-item :label="t('admin.forms.section.lifecycleConfirmation')" required>
            <a-space direction="vertical" fill>
              <a-typography-paragraph copyable code>
                {{ lifecycleConfirmation }}
              </a-typography-paragraph>
              <a-input
                v-model="lifecycleForm.confirmation"
                :placeholder="t('admin.forms.section.lifecycleConfirmationPlaceholder')"
                allow-clear
              />
            </a-space>
          </a-form-item>
        </a-form>
      </a-space>
    </a-modal>

    <a-modal
      v-model:visible="migrationModalVisible"
      :title="t('admin.forms.section.lifecycleMigrateTitle')"
      :ok-text="t('admin.forms.section.lifecycleMigrateAction')"
      :ok-button-props="{ disabled: !migrationReady, loading: migrationForm.processing }"
      :mask-closable="!migrationForm.processing"
      :closable="!migrationForm.processing"
      unmount-on-close
      @ok="migrateTopics"
    >
      <a-form layout="vertical">
        <a-alert
          type="info"
          :title="t('admin.forms.section.lifecycleMigrateHelp', { count: impact.topics })"
          show-icon
        />
        <a-form-item :label="t('admin.forms.section.lifecycleMigrationTarget')" required>
          <a-select
            v-model="migrationForm.target_section_id"
            :placeholder="t('admin.forms.section.lifecycleMigrationTargetPlaceholder')"
            allow-search
          >
            <a-option v-for="target in migrationTargets" :key="target.id" :value="target.id">
              {{ target.category ? `${target.category} / ${target.name}` : target.name }}
            </a-option>
          </a-select>
        </a-form-item>
        <a-form-item :label="t('admin.forms.section.lifecycleReason')" required>
          <a-textarea
            v-model="migrationForm.reason"
            :max-length="1000"
            show-word-limit
            :auto-size="{ minRows: 3, maxRows: 6 }"
            :placeholder="t('admin.forms.section.lifecycleMigrationReasonPlaceholder')"
          />
        </a-form-item>
      </a-form>
    </a-modal>

    <a-modal
      v-model:visible="destroyModalVisible"
      :title="t('admin.forms.section.lifecycleDeleteTitle')"
      :ok-text="t('admin.forms.section.lifecycleDeleteAction')"
      :ok-button-props="{ status: 'danger', disabled: !destroyReady, loading: destroyForm.processing }"
      :mask-closable="!destroyForm.processing"
      :closable="!destroyForm.processing"
      unmount-on-close
      @ok="destroySection"
    >
      <a-space direction="vertical" :size="16" fill>
        <a-alert type="error" :title="t('admin.forms.section.lifecycleDeleteHelp')" show-icon />
        <a-alert
          v-if="destroyBlockers.length"
          type="warning"
          :title="t('admin.forms.section.lifecycleDeleteBlocked')"
          show-icon
        >
          <a-list size="small" :bordered="false">
            <a-list-item v-for="blocker in destroyBlockers" :key="blocker">
              {{ blocker }}
            </a-list-item>
          </a-list>
        </a-alert>
        <a-form layout="vertical">
          <a-form-item :label="t('admin.forms.section.lifecycleReason')" required>
            <a-textarea
              v-model="destroyForm.reason"
              :max-length="1000"
              show-word-limit
              :auto-size="{ minRows: 3, maxRows: 6 }"
              :placeholder="t('admin.forms.section.lifecycleDeleteReasonPlaceholder')"
            />
          </a-form-item>
          <a-form-item :label="t('admin.forms.section.lifecycleConfirmation')" required>
            <a-space direction="vertical" fill>
              <a-typography-paragraph copyable code>
                {{ confirmations.destroy }}
              </a-typography-paragraph>
              <a-input
                v-model="destroyForm.confirmation"
                :placeholder="t('admin.forms.section.lifecycleConfirmationPlaceholder')"
                allow-clear
              />
            </a-space>
          </a-form-item>
        </a-form>
      </a-space>
    </a-modal>
  </a-space>
</template>
