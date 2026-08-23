<script setup lang="ts">
import { computed, ref } from 'vue'
import { Message } from '@arco-design/web-vue'
import { router, usePage } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import { IconBug, IconCopy, IconLaunch } from '@arco-design/web-vue/es/icon'
import { adminRoutes } from '@/lib/adminRoutes'
import { documentFrontendApplicationId } from '@/lib/frontendApplications'
import { performSharedAction } from '@/lib/sharedAction'
import { navigateFrontendDocument } from '@/lib/applicationNavigation'
import { confirmUnsavedNavigation } from '@/lib/unsavedForms'

interface Persona {
  key: string
  available: boolean
}

interface DeveloperModePayload {
  enabled: boolean
  profile?: string
  environment?: string
  production_environment?: boolean
  request_id?: string
  workbench_access?: boolean
  tools_access?: boolean
  current_persona?: string
  persona_switch_url?: string
  personas?: Persona[]
}

const page = usePage()
const { locale, t } = useI18n()
const visible = ref(false)
const switchingPersona = ref<string | null>(null)

const developerMode = computed(
  () =>
    (page.props.developer_mode ?? { enabled: false }) as DeveloperModePayload,
)

const diagnosticSummary = computed(() => ({
  application: 'McWeb',
  environment: developerMode.value.environment ?? 'unknown',
  developerMode: {
    enabled: developerMode.value.enabled,
    profile: developerMode.value.profile ?? 'unknown',
    productionEnvironment:
      developerMode.value.production_environment === true,
  },
  frontend: {
    component: page.component,
    locale: locale.value,
    requestId: developerMode.value.request_id ?? null,
  },
}))

async function copyDiagnostics() {
  try {
    await navigator.clipboard.writeText(
      JSON.stringify(diagnosticSummary.value, null, 2),
    )
    Message.success(t('common.developerDiagnosticsCopied'))
  } catch {
    Message.error(t('common.developerDiagnosticsCopyFailed'))
  }
}

function openWorkbench() {
  visible.value = false
  router.visit(adminRoutes.developerWorkbench)
}

async function switchPersona(persona: Persona) {
  const url = developerMode.value.persona_switch_url
  if (!url || !persona.available || switchingPersona.value) return
  if (!confirmUnsavedNavigation()) return

  switchingPersona.value = persona.key
  try {
    await performSharedAction(documentFrontendApplicationId(), url, {
      method: 'POST',
      data: { persona: persona.key },
    })
    navigateFrontendDocument('/app')
  } finally {
    switchingPersona.value = null
  }
}
</script>

<template>
  <template v-if="developerMode.enabled">
    <a-back-top :visible-height="-1">
      <a-button
        type="primary"
        status="warning"
        shape="circle"
        :aria-label="t('common.openDeveloperTools')"
        @click.stop="visible = true"
      >
        <template #icon><icon-bug /></template>
      </a-button>
    </a-back-top>

    <a-drawer
      v-model:visible="visible"
      :title="t('common.developerTools')"
      :width="'min(440px, 100vw)'"
      :footer="false"
      unmount-on-close
    >
      <a-watermark
        :content="t('common.developerModeBadge')"
        :gap="[120, 96]"
        :rotate="-18"
        :alpha="0.08"
        :font="{ color: '#f53f3f', fontSize: 24, fontWeight: 700 }"
      >
        <a-space direction="vertical" :size="16" fill>
          <a-alert
            type="warning"
            show-icon
            :title="t('common.developerMode')"
          >
            {{ t('common.developerModeWarning') }}
          </a-alert>

          <a-descriptions :column="1" bordered size="small">
            <a-descriptions-item :label="t('common.developerProfile')">
              <a-tag color="orangered">{{ developerMode.profile }}</a-tag>
            </a-descriptions-item>
            <a-descriptions-item :label="t('common.developerEnvironment')">
              {{ developerMode.environment }}
            </a-descriptions-item>
            <a-descriptions-item :label="t('common.developerPageComponent')">
              <a-typography-text code copyable>{{ page.component }}</a-typography-text>
            </a-descriptions-item>
            <a-descriptions-item :label="t('common.developerRequestId')">
              <a-typography-text code copyable>
                {{ developerMode.request_id ?? t('common.notAvailable') }}
              </a-typography-text>
            </a-descriptions-item>
          </a-descriptions>

          <a-card
            v-if="developerMode.tools_access"
            :title="t('common.developerPersonas')"
            :bordered="true"
          >
            <a-space direction="vertical" :size="12" fill>
              <a-space wrap>
                <a-button
                  v-for="persona in developerMode.personas ?? []"
                  :key="persona.key"
                  :type="developerMode.current_persona === persona.key ? 'primary' : 'outline'"
                  :disabled="!persona.available"
                  :loading="switchingPersona === persona.key"
                  @click="switchPersona(persona)"
                >
                  {{ t(`common.developerPersona.${persona.key}`) }}
                </a-button>
              </a-space>
              <a-empty
                v-if="!(developerMode.personas ?? []).some((persona) => persona.available)"
                :description="t('common.developerPersonasEmpty')"
              />
            </a-space>
          </a-card>

          <a-space direction="vertical" fill>
            <a-button long @click="copyDiagnostics">
              <template #icon><icon-copy /></template>
              {{ t('common.copyDeveloperDiagnostics') }}
            </a-button>
            <a-button
              v-if="developerMode.workbench_access"
              type="primary"
              long
              @click="openWorkbench"
            >
              <template #icon><icon-launch /></template>
              {{ t('common.openDeveloperWorkbench') }}
            </a-button>
          </a-space>
        </a-space>
      </a-watermark>
    </a-drawer>
  </template>
</template>
