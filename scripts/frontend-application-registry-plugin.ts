import { resolve } from 'node:path'
import type { Plugin, ViteDevServer } from 'vite'
import type { FrontendApplicationRegistryData } from '../app/javascript/lib/frontendApplicationTypes.ts'
import { readFrontendApplicationRegistry } from './frontend-application-registry.ts'

export const FRONTEND_APPLICATION_REGISTRY_MODULE = 'virtual:mcweb/frontend-applications'
const resolvedModuleId = `\0${FRONTEND_APPLICATION_REGISTRY_MODULE}`

export function frontendApplicationRegistryModuleSource(registry: FrontendApplicationRegistryData): string {
  const serialized = JSON.stringify(registry)
    .replaceAll('<', '\\u003c')
    .replaceAll('\u2028', '\\u2028')
    .replaceAll('\u2029', '\\u2029')
  // Keep this module data-only. The browser hydrates/freeze-locks this snapshot;
  // it must never import the compiler or the raw JSON manifest graph.
  return `export default ${serialized};\n`
}

export function frontendApplicationRegistryPlugin(repositoryRoot: string): Plugin {
  const registryRoot = resolve(repositoryRoot, 'config/frontend_applications').replaceAll('\\', '/')
  let devServer: ViteDevServer | undefined
  const registryChanged = (file: string) => {
    const normalized = resolve(file).replaceAll('\\', '/')
    if (!normalized.startsWith(`${registryRoot}/`) || !normalized.endsWith('.json')) return
    const module = devServer?.moduleGraph.getModuleById(resolvedModuleId)
    if (module) devServer?.moduleGraph.invalidateModule(module)
    // A registry change can alter any application's ownership or route order.
    // Always reload, including additions/removals, and let load fail visibly on
    // invalid input instead of retaining a previously compiled registry.
    devServer?.ws.send({ type: 'full-reload' })
  }

  return {
    name: 'mcweb-frontend-application-registry',
    buildStart() {
      // Validate even if an entrypoint accidentally stops importing the module.
      const { files, directories } = readFrontendApplicationRegistry(repositoryRoot)
      for (const file of [...directories, ...files]) this.addWatchFile(file)
    },
    resolveId(id) {
      return id === FRONTEND_APPLICATION_REGISTRY_MODULE ? resolvedModuleId : null
    },
    load(id) {
      if (id !== resolvedModuleId) return null
      const { registry, files } = readFrontendApplicationRegistry(repositoryRoot)
      for (const file of files) this.addWatchFile(file)
      return frontendApplicationRegistryModuleSource(registry)
    },
    configureServer(server) {
      devServer = server
      server.watcher.add(registryRoot)
      server.watcher.on('add', registryChanged)
      server.watcher.on('change', registryChanged)
      server.watcher.on('unlink', registryChanged)
    },
    closeBundle() {
      devServer?.watcher.off('add', registryChanged)
      devServer?.watcher.off('change', registryChanged)
      devServer?.watcher.off('unlink', registryChanged)
      devServer = undefined
    },
    generateBundle(_options, bundle) {
      for (const output of Object.values(bundle)) {
        if (output.type !== 'chunk') continue
        for (const id of Object.keys(output.modules)) {
          const normalized = id.replaceAll('\\', '/')
          if (/\/scripts\/frontend-application-registry(?:-compiler|-plugin)?\.ts(?:$|\?)/.test(normalized)
            || /\/config\/frontend_applications\/.*\.json(?:$|\?)/.test(normalized)) {
            this.error(`Build-only frontend registry module leaked into ${output.fileName}: ${id}`)
          }
        }
      }
    },
  }
}
