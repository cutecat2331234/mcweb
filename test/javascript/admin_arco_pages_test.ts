import assert from 'node:assert/strict'
import { readFileSync, readdirSync } from 'node:fs'
import test from 'node:test'

function pageSource(relativePath: string) {
  return readFileSync(new URL(`../../app/javascript/pages/Admin/${relativePath}`, import.meta.url), 'utf8')
}

function adminComponentSource(relativePath: string) {
  return readFileSync(
    new URL(`../../app/javascript/components/admin/${relativePath}`, import.meta.url),
    'utf8',
  )
}

function javascriptSource(relativePath: string) {
  return readFileSync(new URL(`../../app/javascript/${relativePath}`, import.meta.url), 'utf8')
}

function projectSource(relativePath: string) {
  return readFileSync(new URL(`../../${relativePath}`, import.meta.url), 'utf8')
}

function allAdminPageSources() {
  const root = new URL('../../app/javascript/pages/Admin/', import.meta.url)
  const paths = readdirSync(root, { recursive: true, encoding: 'utf8' })
  return paths
    .filter((relativePath) => relativePath.endsWith('.vue'))
    .map((relativePath) => readFileSync(new URL(relativePath.replaceAll('\\', '/'), root), 'utf8'))
}

function assertNoLegacyPagePrimitives(source: string) {
  assert.doesNotMatch(source, /@\/components\/ui\//)
  assert.doesNotMatch(source, /@\/components\/portal\/(?:PageHeader|Pagination|BulkModerateToolbar)\.vue/)
}

function assertNoNativeAdminControls(source: string) {
  assert.doesNotMatch(source, /<(?:input|select|button|table)(?:\s|>)/i)
}

test('generic admin index uses Arco for navigation, table, empty state, and pagination', () => {
  const source = pageSource('Generic/Index.vue')

  assertNoLegacyPagePrimitives(source)
  assert.match(source, /<a-page-header/)
  assert.match(source, /<a-tabs/)
  assert.match(source, /<a-date-picker/)
  assert.match(source, /<a-table/)
  assert.match(source, /window\.matchMedia\('\(max-width: 1023px\)'\)/)
  assert.match(source, /<a-dropdown[\s\S]*?bulkModerate/)
  assert.doesNotMatch(source, /<Link\b|class="arco-btn/)
  assert.match(source, /<a-empty/)
  assert.match(source, /<a-pagination/)
  assert.match(source, /v-if="!isMobile"/)
  assert.match(source, /<a-list v-else/)
  assert.match(source, /v-if="pagination"/)
  assert.match(source, /paginationSummary/)
  assert.match(source, /size="medium"/)
  assert.doesNotMatch(source, /pagination && pagination\.pages > 1/)
  assert.doesNotMatch(source, /admin-generic-index__table-card/)
  assert.match(source, /router\.visit/)
  assert.match(source, /router\.patch/)
})

test('generic admin show keeps action forms and renders them with Arco controls', () => {
  const source = pageSource('Generic/Show.vue')

  assertNoLegacyPagePrimitives(source)
  assert.match(source, /<a-page-header/)
  assert.match(source, /<a-descriptions/)
  assert.match(source, /<a-card/)
  assert.match(source, /<a-input/)
  assert.match(source, /<a-select/)
  assert.match(source, /<a-checkbox/)
  assert.match(source, /useForm/)
  assert.match(source, /router\.visit/)
  assert.match(source, /router\.post/)
  assert.match(source, /router\.patch/)
})

test('admin dashboard uses Arco statistics, health, cards, table, and empty state', () => {
  const source = pageSource('Dashboard/Index.vue')

  assertNoLegacyPagePrimitives(source)
  assert.match(source, /<a-page-header/)
  assert.match(source, /<a-statistic/)
  assert.match(source, /<a-alert/)
  assert.match(source, /<a-card/)
  assert.match(source, /<a-table/)
  assert.match(source, /<a-empty/)
})

test('topic field form uses Arco controls while retaining nested errors and mutations', () => {
  const source = pageSource('Forum/TopicFields/Form.vue')

  assertNoLegacyPagePrimitives(source)
  assert.match(source, /<a-page-header/)
  assert.match(source, /<a-form/)
  assert.match(source, /<a-form-item/)
  assert.match(source, /<a-input/)
  assert.match(source, /<a-select/)
  assert.match(source, /<a-textarea/)
  assert.match(source, /<a-checkbox/)
  assert.match(source, /<a-checkbox-group/)
  assert.match(source, /<a-input-number/)
  assert.match(source, /<a-card/)
  assert.match(source, /<a-space/)
  assert.match(source, /<a-alert/)
  assert.match(source, /<a-button/)
  assert.match(source, /fieldError\(/)
  assert.match(source, /topic_field\.section_ids/)
  assert.match(source, /topic_field\.editable_group_ids/)
  assert.match(source, /form\.patch\(props\.submitUrl\)/)
  assert.match(source, /form\.post\(props\.submitUrl\)/)
  assert.match(source, /:loading="form\.processing"/)
})

test('system API key pages use Arco controls while retaining create and revoke mutations', () => {
  const form = pageSource('System/ApiKeys/Form.vue')
  const index = pageSource('System/ApiKeys/Index.vue')

  for (const source of [form, index]) {
    assertNoLegacyPagePrimitives(source)
    assertNoNativeAdminControls(source)
    assert.match(source, /<a-page-header/)
    assert.match(source, /<a-card/)
  }

  assert.match(form, /<a-form/)
  assert.match(form, /<a-input/)
  assert.match(form, /<a-checkbox/)
  assert.match(form, /<a-button/)
  assert.match(form, /api_key/)
  assert.match(form, /form\.post\(props\.submitUrl\)/)

  assert.match(index, /<a-table/)
  assert.match(index, /<a-tag/)
  assert.match(index, /<a-empty/)
  assert.match(index, /router\.post\(key\.revokeUrl\)/)
})

test('system email ban form uses Arco controls while retaining all mutations', () => {
  const source = pageSource('System/EmailBans/Form.vue')

  assertNoLegacyPagePrimitives(source)
  assertNoNativeAdminControls(source)
  assert.match(source, /<a-page-header/)
  assert.match(source, /<a-card/)
  assert.match(source, /<a-form/)
  assert.match(source, /<a-input/)
  assert.match(source, /<a-textarea/)
  assert.match(source, /<a-date-picker/)
  assert.match(source, /email_ban/)
  assert.match(source, /form\.post\(props\.submitUrl\)/)
  assert.match(source, /form\.patch\(props\.submitUrl\)/)
  assert.match(source, /form\.delete\(props\.deleteUrl\)/)
})

test('system feature toggles use an Arco list, alerts, and switches while retaining the portal invariant', () => {
  const source = pageSource('System/FeatureToggles/Show.vue')

  assertNoLegacyPagePrimitives(source)
  assertNoNativeAdminControls(source)
  assert.match(source, /<a-page-header/)
  assert.match(source, /<a-alert/)
  assert.match(source, /<a-list/)
  assert.match(source, /<a-list-item/)
  assert.match(source, /<a-list-item-meta/)
  assert.match(source, /<a-switch/)
  assert.match(source, /!form\.features\.forum && !form\.features\.store/)
  assert.match(source, /form\.patch\(adminRoutes\.featureToggles\)/)
})

test('system settings use an Arco form while retaining the nested settings mutation', () => {
  const source = pageSource('System/Settings/Show.vue')

  assertNoLegacyPagePrimitives(source)
  assertNoNativeAdminControls(source)
  assert.match(source, /<a-page-header/)
  assert.match(source, /<a-card/)
  assert.match(source, /<a-form/)
  assert.match(source, /setting\.control === 'boolean'/)
  assert.match(source, /<a-select/)
  assert.match(source, /setting\.enabled_value/)
  assert.match(source, /setting\.disabled_value/)
  assert.match(source, /<a-input/)
  assert.match(source, /<a-button/)
  assert.match(source, /settings\.\$\{key\}/)
  assert.match(source, /form\.patch\(adminRoutes\.settings\)/)
})

test('system webhook pages use Arco controls while retaining nested mutations and edit links', () => {
  const form = pageSource('System/WebhookSubscriptions/Form.vue')
  const index = pageSource('System/WebhookSubscriptions/Index.vue')

  for (const source of [form, index]) {
    assertNoLegacyPagePrimitives(source)
    assertNoNativeAdminControls(source)
    assert.match(source, /<a-page-header/)
    assert.match(source, /<a-card/)
  }

  assert.match(form, /<a-form/)
  assert.match(form, /<a-input/)
  assert.match(form, /<a-select/)
  assert.match(form, /<a-switch/)
  assert.match(form, /webhook_subscription/)
  assert.match(form, /form\.post\(props\.submitUrl\)/)
  assert.match(form, /form\.patch\(props\.submitUrl\)/)
  assert.match(form, /form\.delete\(props\.deleteUrl\)/)

  assert.match(index, /<a-table/)
  assert.match(index, /<a-tag/)
  assert.match(index, /<a-empty/)
  assert.match(index, /:href="record\.editUrl"/)
})

const forumArcoPagePaths = [
  'Forum/Attachments/Index.vue',
  'Forum/Badges/Form.vue',
  'Forum/CannedResponses/Form.vue',
  'Forum/Categories/Form.vue',
  'Forum/CensoredWords/Index.vue',
  'Forum/CustomBbcodes/Form.vue',
  'Forum/HelpArticles/Form.vue',
  'Forum/Notices/Form.vue',
  'Forum/Pages/Form.vue',
  'Forum/Phrases/Form.vue',
  'Forum/Points/Adjust.vue',
  'Forum/Points/Settings.vue',
  'Forum/ReactionTypes/Form.vue',
  'Forum/Sections/Form.vue',
  'Forum/Settings/Show.vue',
  'Forum/Smilies/Form.vue',
  'Forum/Stats/Index.vue',
  'Forum/TagGroups/Form.vue',
  'Forum/Tags/Form.vue',
  'Forum/Themes/Form.vue',
  'Forum/UserFields/Form.vue',
  'Forum/UserGroups/Form.vue',
  'Forum/UserTitles/Form.vue',
  'Forum/WarningTemplates/Form.vue',
]

test('forum specialized pages use Arco without legacy or native admin controls', () => {
  for (const relativePath of forumArcoPagePaths) {
    const source = pageSource(relativePath)

    assertNoLegacyPagePrimitives(source)
    assertNoNativeAdminControls(source)
    assert.doesNotMatch(source, /@\/components\/admin\//)
    assert.doesNotMatch(source, /<textarea(?:\s|>)/i)
    assert.match(source, /<a-page-header/)
  }
})

test('interactive forum pages retain filters, mutations, confirmation, and nested payloads', () => {
  const attachments = pageSource('Forum/Attachments/Index.vue')
  assert.match(attachments, /<a-table/)
  assert.match(attachments, /<a-pagination/)
  assert.match(attachments, /router\.get\(/)
  assert.match(attachments, /router\.delete\(/)
  assert.match(attachments, /await confirm\(/)

  const settings = pageSource('Forum/Settings/Show.vue')
  assert.match(settings, /<a-checkbox/)
  assert.match(settings, /<a-select/)
  assert.match(settings, /form\.patch\(adminRoutes\.forumSettings\)/)
  assert.match(settings, /router\.post\(props\.testWebhookUrl/)
  assert.match(settings, /setInterval\(pollWebhookStatus, 2000\)/)

  const sections = pageSource('Forum/Sections/Form.vue')
  assert.match(sections, /<a-checkbox-group/)
  assert.match(sections, /form\.section\.required_tag_ids/)
  assert.match(sections, /form\.section\.required_tag_group_ids/)
  assert.match(sections, /form\.section\.allowed_tag_ids/)
  assert.match(sections, /form\.section\.default_tag_ids/)
  assert.match(sections, /form\.patch\(props\.submitUrl\)/)
  assert.match(sections, /form\.post\(props\.submitUrl\)/)

  const userGroups = pageSource('Forum/UserGroups/Form.vue')
  assert.match(userGroups, /router\.post\(props\.addMemberUrl/)
  assert.match(userGroups, /router\.delete\(member\.remove_url, \{ preserveScroll: true \}\)/)
  assert.match(userGroups, /removeMemberConfirm/)
  assert.match(userGroups, /form\.delete\(props\.deleteUrl\)/)
  assert.match(userGroups, /await confirm\(/)

  const notices = pageSource('Forum/Notices/Form.vue')
  assert.match(notices, /<a-date-picker/)
  assert.match(notices, /form\.patch\(props\.submitUrl\)/)
  assert.match(notices, /form\.post\(props\.submitUrl\)/)
  assert.match(notices, /form\.delete\(props\.deleteUrl\)/)
})

const storeArcoPagePaths = [
  'Store/Categories/Form.vue',
  'Store/Coupons/Form.vue',
  'Store/Fulfillments/Show.vue',
  'Store/GiftCards/Form.vue',
  'Store/MembershipTypes/Form.vue',
  'Store/Orders/IndexProDemo.vue',
  'Store/ProductQuestions/Index.vue',
  'Store/Products/Form.vue',
  'Store/Settings/Show.vue',
  'Store/UserMemberships/Form.vue',
]

test('store specialized pages use Arco without legacy, native, or Element Plus controls', () => {
  for (const relativePath of storeArcoPagePaths) {
    const source = pageSource(relativePath)

    assertNoLegacyPagePrimitives(source)
    assertNoNativeAdminControls(source)
    assert.doesNotMatch(source, /@\/components\/admin-pro\//)
    assert.doesNotMatch(source, /<el-/)
    assert.doesNotMatch(source, /<textarea(?:\s|>)/i)
    assert.match(source, /<a-page-header/)
  }
})

test('store forms retain nested payloads, amount units, associations, and mutations', () => {
  const products = pageSource('Store/Products/Form.vue')
  assert.match(products, /product:\s*\{/)
  assert.match(products, /price_cents/)
  assert.match(products, /compare_at_price_cents/)
  assert.match(products, /form\.product\.prerequisites/)
  assert.match(products, /form\.product\.variants/)
  assert.match(products, /form\.patch\(props\.submitUrl\)/)
  assert.match(products, /form\.post\(props\.submitUrl\)/)
  assert.match(products, /body\.append\('file', file\)/)
  assert.match(products, /<a-upload/)
  assert.match(products, /value-format="YYYY-MM-DDTHH:mm"/)

  const coupons = pageSource('Store/Coupons/Form.vue')
  assert.match(coupons, /coupon:\s*\{ \.\.\.props\.coupon \}/)
  assert.match(coupons, /min_amount_cents/)
  assert.match(coupons, /max_discount_cents/)
  assert.match(coupons, /toggleProductId/)
  assert.match(coupons, /toggleCategoryId/)
  assert.match(coupons, /form\.patch\(props\.submitUrl\)/)
  assert.match(coupons, /form\.post\(props\.submitUrl\)/)

  for (const relativePath of [
    'Store/Categories/Form.vue',
    'Store/GiftCards/Form.vue',
    'Store/MembershipTypes/Form.vue',
  ]) {
    const source = pageSource(relativePath)
    assert.match(source, /form\.patch\(props\.submitUrl\)/)
    assert.match(source, /form\.post\(props\.submitUrl\)/)
  }

  const userMemberships = pageSource('Store/UserMemberships/Form.vue')
  assert.match(userMemberships, /user_membership:\s*\{/)
  assert.match(userMemberships, /form\.post\(props\.submitUrl\)/)
})

test('store operational pages retain filters, bulk actions, retries, moderation, and webhook polling', () => {
  const orders = pageSource('Store/Orders/IndexProDemo.vue')
  assert.match(orders, /router\.get\(/)
  assert.match(orders, /router\.patch\(/)
  assert.match(orders, /ids: selectedRowKeys\.value/)
  assert.match(orders, /action_type: action/)
  assert.match(orders, /return_to:/)
  assert.match(orders, /<a-table/)
  assert.match(orders, /<a-pagination/)

  const fulfillments = pageSource('Store/Fulfillments/Show.vue')
  assert.match(fulfillments, /method="patch"/)
  assert.match(fulfillments, /:data="\{ retry: '1' \}"/)
  assert.match(fulfillments, /adminRoutes\.storeFulfillment/)

  const questions = pageSource('Store/ProductQuestions/Index.vue')
  assert.match(questions, /<a-table/)
  assert.match(questions, /router\.patch\(url\)/)

  const settings = pageSource('Store/Settings/Show.vue')
  assert.match(settings, /store_features:/)
  assert.match(settings, /payload\.shipping_methods/)
  assert.match(settings, /\.patch\(adminRoutes\.storeSettings\)/)
  assert.match(settings, /router\.post\(/)
  assert.match(settings, /setInterval\(pollWebhookStatus, 2000\)/)
  assert.match(settings, /await confirm\(/)
})

const websiteArcoPagePaths = [
  'Website/Articles/Form.vue',
  'Website/NavItems/Index.vue',
  'Website/Pages/Form.vue',
  'Website/Pages/Revisions/Index.vue',
  'Website/Pages/Revisions/Show.vue',
  'Website/Themes/Form.vue',
]

const minecraftArcoPagePaths = [
  'Minecraft/IntegrationActions/Form.vue',
  'Minecraft/Nodes/Form.vue',
  'Minecraft/Nodes/Show.vue',
  'Minecraft/PermissionGroupMappings/Show.vue',
  'Minecraft/Players/Index.vue',
  'Minecraft/ProfileFields/Form.vue',
  'Minecraft/Servers/Form.vue',
  'Minecraft/Servers/Show.vue',
  'Minecraft/Settings/Show.vue',
]

test('website, frontend, Minecraft, and compatibility demo pages use only Arco admin controls', () => {
  for (const relativePath of [
    ...websiteArcoPagePaths,
    ...minecraftArcoPagePaths,
    'Frontend/Templates/Index.vue',
    'DashboardProDemo.vue',
  ]) {
    const source = pageSource(relativePath)

    assertNoLegacyPagePrimitives(source)
    assertNoNativeAdminControls(source)
    assert.doesNotMatch(source, /@\/components\/admin-pro\//)
    assert.doesNotMatch(source, /<el-/)
    assert.match(source, /<a-(?:page-header|card)/)
  }
})

test('admin-only shared components use Arco instead of legacy and native controls', () => {
  for (const relativePath of [
    'AdminAlertBanners.vue',
    'AdminFlashMessages.vue',
    'AdminLanguageSwitcher.vue',
    'MarkdownEditor.vue',
    'MetricHistoryPanel.vue',
    'NodeTasksTable.vue',
    'website/BlockEditor.vue',
    'website/SeoFields.vue',
    'website/TranslationsPanel.vue',
  ]) {
    const source = adminComponentSource(relativePath)

    assert.doesNotMatch(source, /@\/components\/ui\//)
    assertNoNativeAdminControls(source)
    assert.doesNotMatch(source, /<el-/)
    assert.match(source, /<a-/)
  }
})

test('website and frontend Arco pages retain publishing, ordering, upload, and destructive confirmations', () => {
  const templates = pageSource('Frontend/Templates/Index.vue')
  assert.match(templates, /<a-upload/)
  assert.match(templates, /router\.post\(/)
  assert.match(templates, /router\.patch\(/)
  assert.match(templates, /router\.delete\(/)
  assert.match(templates, /Modal\.warning\(/)

  const nav = pageSource('Website/NavItems/Index.vue')
  assert.match(nav, /<a-table/)
  assert.match(nav, /item_ids: ids/)
  assert.match(nav, /router\.patch\(props\.reorderUrl/)
  assert.match(nav, /router\.delete\(/)
  assert.match(nav, /Modal\.warning\(/)

  for (const relativePath of ['Website/Articles/Form.vue', 'Website/Pages/Form.vue']) {
    const source = pageSource(relativePath)
    assert.match(source, /<a-tabs/)
    assert.match(source, /<a-date-picker/)
    assert.match(source, /form\.patch\(props\.submitUrl\)/)
    assert.match(source, /form\.post\(props\.submitUrl\)/)
    assert.match(source, /publish_at: scheduleAt\.value/)
    assert.match(source, /Modal\.warning\(/)
  }

  const pages = pageSource('Website/Pages/Form.vue')
  assert.match(pages, /<BlockEditor/)
  assert.match(pages, /<SeoFields/)
  assert.match(pages, /<TranslationsPanel/)
})

test('Minecraft Arco pages retain commands, task details, mappings, and confirmation gates', () => {
  const server = pageSource('Minecraft/Servers/Show.vue')
  assert.match(server, /<NodeTasksTable/)
  assert.match(server, /<MetricHistoryPanel/)
  assert.match(server, /router\.post\(props\.controlUrls\.exec/)
  assert.match(server, /router\.delete\(action\.href\)/)
  assert.match(server, /Modal\.warning\(/)

  const node = pageSource('Minecraft/Nodes/Show.vue')
  assert.match(node, /<a-table/)
  assert.match(node, /router\.post\(action\.href\)/)
  assert.match(node, /Modal\.warning\(/)

  const players = pageSource('Minecraft/Players/Index.vue')
  assert.match(players, /<a-table/)
  assert.match(players, /router\.post\(props\.kickUrl/)
  assert.match(players, /Modal\.warning\(/)

  const mappings = pageSource('Minecraft/PermissionGroupMappings/Show.vue')
  assert.match(mappings, /router\.patch|router\.post/)
  assert.match(mappings, /router\.delete\(/)
  assert.match(mappings, /Modal\.warning\(/)
})

test('Arco admin shell selects parent items on detail routes and keeps mobile groups synchronized', () => {
  const source = javascriptSource('layouts/ArcoAdminLayout.vue')

  assert.match(source, /const activeItemHref = computed/)
  assert.match(source, /:selected-keys="activeItemHref \? \[activeItemHref\] : \[\]"/)
  assert.match(source, /v-model:open-keys="openKeys"/)
  assert.doesNotMatch(source, /`m-\$\{group\.key\}`/)
  assert.match(source, /min\(280px, 100vw\)/)
  assert.match(source, /id="admin-content"/)
  assert.match(source, /arco-admin-skip-link/)
  assert.match(source, /<a-scrollbar/)
  assert.match(source, /type="embed"/)
  assert.match(source, /height: '100dvh'/)
  assert.match(source, /background: 'var\(--color-bg-1\)'/)
  assert.match(source, /background: 'var\(--color-fill-1\)'/)
  assert.doesNotMatch(source, /background: 'var\(--color-fill-2\)'/)
  assert.match(source, /'--color-border-2': 'var\(--color-border-3\)'/)
  assert.match(source, /arco-admin-sider__menu-scroll/)
  assert.match(source, /scrollbar-width:\s*none/)
  assert.match(source, /arco-admin-nav-trigger--mobile/)
  assert.match(source, /arco-admin-nav-trigger--desktop/)
  assert.match(source, /arco-page-header-subtitle/)
  assert.match(source, /white-space:\s*normal/)
  assert.match(source, /@media \(max-width:\s*1023px\)/)
  assert.match(source, /@media \(min-width:\s*1024px\)/)
  assert.doesNotMatch(source, /overflow:\s*auto/)
  assert.doesNotMatch(source, /@\/components\/portal\//)
})

test('admin entry bundles Arco without registering legacy Element Plus runtimes', () => {
  const source = javascriptSource('entrypoints/admin.ts')

  assert.match(source, /\.use\(ArcoVue\)/)
  assert.doesNotMatch(source, /from ['"]element-plus['"]/)
  assert.doesNotMatch(source, /plus-pro-components/)
  assert.doesNotMatch(source, /styles\/admin\.css/)
  assert.doesNotMatch(source, /AppProvider/)
})

test('every reachable admin page is free of legacy controls and uses the Arco confirm facade', () => {
  for (const source of allAdminPageSources()) {
    assertNoLegacyPagePrimitives(source)
    assertNoNativeAdminControls(source)
    assert.doesNotMatch(source, /<el-/)
    assert.doesNotMatch(source, /@\/components\/admin-pro\//)
    assert.doesNotMatch(source, /@\/components\/portal\//)
    assert.doesNotMatch(source, /@\/lib\/useConfirm/)
    assert.doesNotMatch(source, /<a-form\b[^>]*@submit\.prevent/)
    assert.doesNotMatch(
      source,
      /\{ xs: [^,}]+, (?:lg|xl):/,
      'responsive objects must cover the intermediate sm breakpoint',
    )
  }

  const confirmSource = javascriptSource('lib/arcoConfirm.ts')
  assert.match(confirmSource, /Modal\.warning\(config\)/)
  assert.match(confirmSource, /Modal\.confirm\(config\)/)
  assert.match(confirmSource, /Promise<boolean>/)
  assert.match(confirmSource, /onClose: \(\) => finish\(false\)/)
})

test('former Pro compatibility components and package dependencies are Arco-only', () => {
  const proLayout = javascriptSource('components/admin-pro/ProLayout.vue')
  const proTable = javascriptSource('components/admin-pro/ProTable.vue')
  const compatibilityCss = javascriptSource('styles/admin.css')
  const packageJson = projectSource('package.json')

  assert.match(proLayout, /ArcoAdminLayout/)
  assert.match(proTable, /<a-table/)
  assert.match(proTable, /<a-pagination/)
  assert.match(proTable, /paginationSummary/)
  assert.match(proTable, /<a-grid/)
  assert.doesNotMatch(proLayout + proTable + compatibilityCss, /element-plus|<el-|plus-pro/i)
  assert.doesNotMatch(packageJson, /element-plus|plus-pro-components/i)
})
