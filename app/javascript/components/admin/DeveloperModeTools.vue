<script setup lang="ts">
import { computed, ref } from 'vue'
import { Message } from '@arco-design/web-vue'
import { router, usePage } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import { IconBug, IconCopy, IconLaunch } from '@arco-design/web-vue/es/icon'
import { adminRoutes } from '@/lib/adminRoutes'

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

function switchPersona(persona: Persona) {
  const url = developerMode.value.persona_switch_url
  if (!url || !persona.available || switchingPersona.value) return

  switchingPersona.value = persona.key
  router.post(
    url,
    { persona: persona.key },
    {
      preserveScroll: false,
      preserveState: false,
      onFinish: () => {
        switchingPersona.value = null
      },
    },
  )
}
</script>

<template>
  <template v-if="developerMode.enabled">
    <div
      aria-hidden="true"
      class="pointer-events-none fixed inset-0 z-[1090] flex items-center justify-center overflow-hidden"
    >
      <span
        class="-rotate-12 select-none text-6xl font-black tracking-[0.18em] text-orange-500 opacity-[0.055] md:text-8xl"
      >
        DEV
      </span>
    </div>

    <a-button
      type="primary"
      status="warning"
      shape="round"
      class="!fixed bottom-5 right-5 z-[1095] !shadow-lg"
      :aria-label="t('common.openDeveloperTools')"
      @click="visible = true"
    >
      <template #icon><icon-bug /></template>
      DEV
    </a-button>

    <a-drawer
      v-model:visible="visible"
      :title="t('common.developerTools')"
      :width="'min(440px, 100vw)'"
      :footer="false"
      unmount-on-close
    >
      <a-alert
        type="warning"
        show-icon
        :title="t('common.developerMode')"
        class="mb-4"
      >
        {{ t('common.developerModeWarning') }}
      </a-alert>

      <a-descriptions :column="1" bordered size="small" class="mb-4">
        <a-descriptions-item :label="t('common.developerProfile')">
          <a-tag color="orangered">
            {{ developerMode.profile }}
          </a-tag>
        </a-descriptions-item>
        <a-descriptions-item :label="t('common.developerEnvironment')">
          {{ developerMode.environment }}
        </a-descriptions-item>
        <a-descriptions-item :label="t('common.developerPageComponent')">
          <a-typography-text code copyable>
            {{ page.component }}
          </a-typography-text>
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
        class="mb-4"
      >
        <a-space wrap>
          <a-button
            v-for="persona in developerMode.personas ?? []"
            :key="persona.key"
            :type="
              developerMode.current_persona === persona.key
                ? 'primary'
                : 'outline'
            "
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
          class="mt-3"
        />
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
    </a-drawer>
  </template>
</template>
