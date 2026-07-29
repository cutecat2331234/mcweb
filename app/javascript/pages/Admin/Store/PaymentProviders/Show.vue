<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { router, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  Alert,
  Button,
  Card,
  Checkbox,
  Descriptions,
  DescriptionsItem,
  Divider,
  Form,
  FormItem,
  Input,
  InputPassword,
  Modal,
  PageHeader,
  Radio,
  RadioGroup,
  Space,
  Switch,
  Tag,
  TypographyParagraph,
  TypographyText,
  TypographyTitle,
} from '@mcweb/ui'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

type Mode = 'test' | 'live'

type WebhookCheck = {
  id: string
  ok: boolean
  code: string
}

type ProviderConfiguration = {
  provider: 'stripe'
  enabled: boolean
  mode: Mode
  mode_explicit: boolean
  mode_consistent: boolean
  configuration_complete: boolean
  checkout_ready: boolean
  account_binding: {
    bound: boolean
    connection_current: boolean
  }
  credentials: {
    secret_key: { configured: boolean }
    webhook_secret: { configured: boolean }
  }
  webhook: {
    ready: boolean
    endpoint: string | null
    required_events: string[]
    checks: WebhookCheck[]
  }
  connection_test: {
    allowed: boolean
    token: string | null
    last_status: 'success' | 'failed' | null
    last_error_code: string | null
    last_mode: Mode | null
    last_tested_at: string | null
    current: boolean
  }
}

const props = defineProps<{
  providerConfig: ProviderConfiguration
  updateUrl: string
  testConnectionUrl: string
}>()

const { locale, t } = useI18n()
const connectionModalVisible = ref(false)
const connectionConfirmation = ref('')
const connectionSubmitting = ref(false)

const form = useForm({
  provider_config: {
    enabled: props.providerConfig.enabled,
    mode: props.providerConfig.mode,
    secret_key: '',
    webhook_secret: '',
    clear_secret_key: false,
    clear_webhook_secret: false,
  },
})

watch(
  () => props.providerConfig,
  (config) => {
    form.provider_config.enabled = config.enabled
    form.provider_config.mode = config.mode
    form.provider_config.secret_key = ''
    form.provider_config.webhook_secret = ''
    form.provider_config.clear_secret_key = false
    form.provider_config.clear_webhook_secret = false
  },
)

const canTestConnection = computed(
  () =>
    props.providerConfig.connection_test.allowed &&
    props.providerConfig.configuration_complete &&
    Boolean(props.providerConfig.connection_test.token),
)

const confirmationValid = computed(
  () => connectionConfirmation.value.trim() === props.providerConfig.provider,
)

function statusColor(ok: boolean) {
  return ok ? 'green' : 'orange'
}

function configurationStatusLabel() {
  return props.providerConfig.configuration_complete
    ? t('admin.paymentProviders.complete')
    : t('admin.paymentProviders.incomplete')
}

function formatTime(value: string | null) {
  if (!value) return t('admin.paymentProviders.never')

  return new Intl.DateTimeFormat(locale.value, {
    dateStyle: 'medium',
    timeStyle: 'medium',
  }).format(new Date(value))
}

function credentialPlaceholder(configured: boolean) {
  return configured
    ? t('admin.paymentProviders.credentialConfiguredPlaceholder')
    : t('admin.paymentProviders.credentialMissingPlaceholder')
}

function checkLabel(check: WebhookCheck) {
  return t(`admin.paymentProviders.checkCodes.${check.code}`)
}

function submitConfiguration() {
  form.patch(props.updateUrl, {
    preserveScroll: true,
    onSuccess: () => {
      form.provider_config.secret_key = ''
      form.provider_config.webhook_secret = ''
      form.provider_config.clear_secret_key = false
      form.provider_config.clear_webhook_secret = false
    },
  })
}

function openConnectionTest() {
  if (!canTestConnection.value) return

  connectionConfirmation.value = ''
  connectionModalVisible.value = true
}

function closeConnectionTest() {
  if (connectionSubmitting.value) return

  connectionModalVisible.value = false
  connectionConfirmation.value = ''
}

function submitConnectionTest() {
  const token = props.providerConfig.connection_test.token
  if (!token || !confirmationValid.value) return

  router.post(
    props.testConnectionUrl,
    {
      token,
      confirmation: connectionConfirmation.value.trim(),
    },
    {
      preserveScroll: true,
      onStart: () => {
        connectionSubmitting.value = true
      },
      onSuccess: () => {
        connectionModalVisible.value = false
        connectionConfirmation.value = ''
      },
      onFinish: () => {
        connectionSubmitting.value = false
      },
    },
  )
}
</script>

<template>
  <section class="min-w-0">
    <PageHeader
      :title="t('admin.paymentProviders.title')"
      :subtitle="t('admin.paymentProviders.subtitle')"
      :show-back="false"
      class="mb-4 !px-0"
    />

    <Alert
      type="info"
      show-icon
      :closable="false"
      :title="t('admin.paymentProviders.secretNotice')"
      class="mb-4"
    />

    <div class="mb-4 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
      <Card :bordered="false" size="small" class="bg-[var(--color-fill-1)]">
        <TypographyText type="secondary">
          {{ t('admin.paymentProviders.provider') }}
        </TypographyText>
        <div class="mt-2">
          <Tag color="arcoblue">Stripe</Tag>
        </div>
      </Card>
      <Card :bordered="false" size="small" class="bg-[var(--color-fill-1)]">
        <TypographyText type="secondary">
          {{ t('admin.paymentProviders.mode') }}
        </TypographyText>
        <div class="mt-2">
          <Tag :color="providerConfig.mode === 'live' ? 'red' : 'blue'">
            {{ t(`admin.paymentProviders.modes.${providerConfig.mode}`) }}
          </Tag>
        </div>
      </Card>
      <Card :bordered="false" size="small" class="bg-[var(--color-fill-1)]">
        <TypographyText type="secondary">
          {{ t('admin.paymentProviders.configuration') }}
        </TypographyText>
        <div class="mt-2">
          <Tag :color="statusColor(providerConfig.configuration_complete)">
            {{ configurationStatusLabel() }}
          </Tag>
        </div>
      </Card>
      <Card :bordered="false" size="small" class="bg-[var(--color-fill-1)]">
        <TypographyText type="secondary">
          {{ t('admin.paymentProviders.checkout') }}
        </TypographyText>
        <div class="mt-2">
          <Tag :color="statusColor(providerConfig.checkout_ready)">
            {{
              providerConfig.checkout_ready
                ? t('admin.paymentProviders.ready')
                : t('admin.paymentProviders.notReady')
            }}
          </Tag>
        </div>
      </Card>
    </div>

    <div class="grid min-w-0 gap-4 xl:grid-cols-[minmax(0,1.45fr)_minmax(20rem,0.85fr)]">
      <Card :bordered="false" class="min-w-0">
        <template #title>
          <div>
            <TypographyTitle :heading="5" class="!mb-0">
              {{ t('admin.paymentProviders.configurationTitle') }}
            </TypographyTitle>
            <TypographyText type="secondary" class="text-sm">
              {{ t('admin.paymentProviders.configurationDescription') }}
            </TypographyText>
          </div>
        </template>

        <Alert
          v-if="form.provider_config.mode === 'live'"
          type="warning"
          show-icon
          :closable="false"
          :title="t('admin.paymentProviders.liveWarning')"
          class="mb-4"
        />

        <Form
          :model="form.provider_config"
          layout="vertical"
          size="large"
          @submit-success="submitConfiguration"
        >
          <div class="grid gap-x-5 md:grid-cols-2">
            <FormItem
              field="mode"
              :label="t('admin.paymentProviders.mode')"
              :extra="t('admin.paymentProviders.modeHelp')"
              required
            >
              <RadioGroup v-model="form.provider_config.mode" type="button">
                <Radio value="test">
                  {{ t('admin.paymentProviders.modes.test') }}
                </Radio>
                <Radio value="live">
                  {{ t('admin.paymentProviders.modes.live') }}
                </Radio>
              </RadioGroup>
            </FormItem>

            <FormItem
              field="enabled"
              :label="t('admin.paymentProviders.enabled')"
              :extra="t('admin.paymentProviders.enabledHelp')"
            >
              <div class="flex min-h-10 items-center gap-3 rounded-lg bg-[var(--color-fill-1)] px-3 py-2">
                <Switch
                  v-model="form.provider_config.enabled"
                  :checked-text="t('admin.paymentProviders.on')"
                  :unchecked-text="t('admin.paymentProviders.off')"
                />
                <TypographyText>
                  {{
                    form.provider_config.enabled
                      ? t('admin.paymentProviders.checkoutEnabled')
                      : t('admin.paymentProviders.checkoutDisabled')
                  }}
                </TypographyText>
              </div>
            </FormItem>
          </div>

          <Divider orientation="left">
            {{ t('admin.paymentProviders.credentials') }}
          </Divider>

          <div class="grid min-w-0 gap-x-5 md:grid-cols-2">
            <FormItem
              field="secret_key"
              :label="t('admin.paymentProviders.secretKey')"
              :extra="t('admin.paymentProviders.blankKeepsExisting')"
            >
              <InputPassword
                v-model="form.provider_config.secret_key"
                allow-clear
                :visibility="false"
                :placeholder="credentialPlaceholder(providerConfig.credentials.secret_key.configured)"
                autocomplete="new-password"
              />
              <Checkbox
                v-if="providerConfig.credentials.secret_key.configured"
                v-model="form.provider_config.clear_secret_key"
                :disabled="Boolean(form.provider_config.secret_key)"
                class="mt-2"
              >
                {{ t('admin.paymentProviders.removeSecretKey') }}
              </Checkbox>
            </FormItem>

            <FormItem
              field="webhook_secret"
              :label="t('admin.paymentProviders.webhookSecret')"
              :extra="t('admin.paymentProviders.blankKeepsExisting')"
            >
              <InputPassword
                v-model="form.provider_config.webhook_secret"
                allow-clear
                :visibility="false"
                :placeholder="credentialPlaceholder(providerConfig.credentials.webhook_secret.configured)"
                autocomplete="new-password"
              />
              <Checkbox
                v-if="providerConfig.credentials.webhook_secret.configured"
                v-model="form.provider_config.clear_webhook_secret"
                :disabled="Boolean(form.provider_config.webhook_secret)"
                class="mt-2"
              >
                {{ t('admin.paymentProviders.removeWebhookSecret') }}
              </Checkbox>
            </FormItem>
          </div>

          <div class="mt-2 flex flex-wrap justify-end gap-3">
            <Button
              html-type="submit"
              type="primary"
              :loading="form.processing"
            >
              {{ t('admin.paymentProviders.save') }}
            </Button>
          </div>
        </Form>
      </Card>

      <Card :bordered="false" class="min-w-0 bg-[var(--color-fill-1)]">
        <template #title>
          <div>
            <TypographyTitle :heading="5" class="!mb-0">
              {{ t('admin.paymentProviders.webhookTitle') }}
            </TypographyTitle>
            <TypographyText type="secondary" class="text-sm">
              {{ t('admin.paymentProviders.webhookDescription') }}
            </TypographyText>
          </div>
        </template>

        <Alert
          :type="providerConfig.webhook.ready ? 'success' : 'warning'"
          show-icon
          :closable="false"
          :title="
            providerConfig.webhook.ready
              ? t('admin.paymentProviders.webhookReady')
              : t('admin.paymentProviders.webhookNeedsAttention')
          "
          class="mb-4"
        />

        <TypographyText type="secondary">
          {{ t('admin.paymentProviders.endpoint') }}
        </TypographyText>
        <TypographyParagraph
          copyable
          class="mt-1 break-all rounded-lg bg-[var(--color-bg-2)] px-3 py-2 font-mono text-xs"
        >
          {{ providerConfig.webhook.endpoint || t('admin.paymentProviders.endpointUnavailable') }}
        </TypographyParagraph>

        <div class="mt-4 space-y-2">
          <div
            v-for="check in providerConfig.webhook.checks"
            :key="check.id"
            class="flex min-w-0 items-start justify-between gap-3 rounded-lg bg-[var(--color-bg-2)] px-3 py-2.5"
          >
            <TypographyText class="min-w-0">
              {{ checkLabel(check) }}
            </TypographyText>
            <Tag :color="check.ok ? 'green' : 'orange'" class="shrink-0">
              {{
                check.ok
                  ? t('admin.paymentProviders.passed')
                  : t('admin.paymentProviders.actionRequired')
              }}
            </Tag>
          </div>
        </div>

        <Divider orientation="left">
          {{ t('admin.paymentProviders.requiredEvents') }}
        </Divider>
        <Space wrap>
          <Tag
            v-for="event in providerConfig.webhook.required_events"
            :key="event"
            color="gray"
            class="max-w-full"
          >
            {{ event }}
          </Tag>
        </Space>
      </Card>
    </div>

    <Card :bordered="false" class="mt-4">
      <template #title>
        <div>
          <TypographyTitle :heading="5" class="!mb-0">
            {{ t('admin.paymentProviders.connectionTitle') }}
          </TypographyTitle>
          <TypographyText type="secondary" class="text-sm">
            {{ t('admin.paymentProviders.connectionDescription') }}
          </TypographyText>
        </div>
      </template>

      <Descriptions
        :column="{ xs: 1, sm: 2, lg: 3 }"
        layout="vertical"
        :bordered="false"
        class="mb-4"
      >
        <DescriptionsItem :label="t('admin.paymentProviders.permission')">
          <Tag :color="providerConfig.connection_test.allowed ? 'green' : 'gray'">
            {{
              providerConfig.connection_test.allowed
                ? t('admin.paymentProviders.allowed')
                : t('admin.paymentProviders.notAllowed')
            }}
          </Tag>
        </DescriptionsItem>
        <DescriptionsItem :label="t('admin.paymentProviders.accountBinding')">
          <Tag :color="providerConfig.account_binding.bound ? 'green' : 'orange'">
            {{
              providerConfig.account_binding.bound
                ? t('admin.paymentProviders.accountBound')
                : t('admin.paymentProviders.accountUnbound')
            }}
          </Tag>
        </DescriptionsItem>
        <DescriptionsItem :label="t('admin.paymentProviders.credentialVerification')">
          <Tag :color="providerConfig.account_binding.connection_current ? 'green' : 'orange'">
            {{
              providerConfig.account_binding.connection_current
                ? t('admin.paymentProviders.verificationCurrent')
                : t('admin.paymentProviders.verificationRequired')
            }}
          </Tag>
        </DescriptionsItem>
        <DescriptionsItem :label="t('admin.paymentProviders.lastResult')">
          <Tag
            v-if="providerConfig.connection_test.last_status"
            :color="providerConfig.connection_test.last_status === 'success' ? 'green' : 'red'"
          >
            {{ t(`admin.paymentProviders.testStatuses.${providerConfig.connection_test.last_status}`) }}
          </Tag>
          <TypographyText v-else type="secondary">
            {{ t('admin.paymentProviders.never') }}
          </TypographyText>
        </DescriptionsItem>
        <DescriptionsItem :label="t('admin.paymentProviders.lastMode')">
          {{
            providerConfig.connection_test.last_mode
              ? t(`admin.paymentProviders.modes.${providerConfig.connection_test.last_mode}`)
              : t('admin.paymentProviders.notAvailable')
          }}
        </DescriptionsItem>
        <DescriptionsItem :label="t('admin.paymentProviders.lastTestedAt')">
          {{ formatTime(providerConfig.connection_test.last_tested_at) }}
        </DescriptionsItem>
      </Descriptions>

      <Alert
        v-if="providerConfig.connection_test.last_error_code"
        type="error"
        show-icon
        :closable="false"
        :title="
          t('admin.paymentProviders.lastError', {
            code: providerConfig.connection_test.last_error_code,
          })
        "
        class="mb-4"
      />

      <div class="flex flex-wrap items-center justify-between gap-3">
        <TypographyText type="secondary">
          {{
            canTestConnection
              ? t('admin.paymentProviders.testReadyHint')
              : t('admin.paymentProviders.testUnavailableHint')
          }}
        </TypographyText>
        <Button
          type="primary"
          status="warning"
          :disabled="!canTestConnection"
          @click="openConnectionTest"
        >
          {{ t('admin.paymentProviders.testConnection') }}
        </Button>
      </div>
    </Card>

    <Modal
      v-model:visible="connectionModalVisible"
      :title="t('admin.paymentProviders.confirmTestTitle')"
      :footer="false"
      :mask-closable="false"
      :esc-to-close="!connectionSubmitting"
      width="min(92vw, 34rem)"
    >
      <Alert
        type="warning"
        show-icon
        :closable="false"
        :title="t('admin.paymentProviders.confirmTestWarning')"
        class="mb-4"
      />
      <Form :model="{ confirmation: connectionConfirmation }" layout="vertical">
        <FormItem
          field="confirmation"
          :label="
            t('admin.paymentProviders.confirmationLabel', {
              provider: providerConfig.provider,
            })
          "
          required
        >
          <Input
            v-model="connectionConfirmation"
            :placeholder="providerConfig.provider"
            autocomplete="off"
            @press-enter="submitConnectionTest"
          />
        </FormItem>
      </Form>
      <div class="flex flex-wrap justify-end gap-2 pt-2">
        <Button :disabled="connectionSubmitting" @click="closeConnectionTest">
          {{ t('admin.paymentProviders.cancel') }}
        </Button>
        <Button
          type="primary"
          status="warning"
          :loading="connectionSubmitting"
          :disabled="!confirmationValid"
          @click="submitConnectionTest"
        >
          {{ t('admin.paymentProviders.runTest') }}
        </Button>
      </div>
    </Modal>
  </section>
</template>
