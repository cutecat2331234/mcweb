import { existsSync, readFileSync, readdirSync } from 'node:fs'
import { relative, resolve } from 'node:path'
import {
  compileFrontendApplicationRegistry,
  type FrontendApplicationManifestSources,
} from './frontend-application-registry-compiler.ts'

export function readFrontendApplicationManifests(repositoryRoot: string) {
  const root = resolve(repositoryRoot)
  const registryRoot = resolve(root, 'config/frontend_applications')
  const directories = [registryRoot, resolve(registryRoot, 'base'), resolve(registryRoot, 'contributions')]
  const files: string[] = []
  const sourceName = (file: string) => relative(root, file).replaceAll('\\', '/')
  const readManifest = (file: string): unknown => {
    // Missing files and malformed JSON are errors, never an empty/stale registry.
    files.push(file)
    try {
      return JSON.parse(readFileSync(file, 'utf8'))
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error)
      throw new Error(`Cannot read frontend application manifest ${sourceName(file)}: ${detail}`, { cause: error })
    }
  }
  const manifestModules = (directory: string, optional = false): Record<string, unknown> => {
    if (optional && !existsSync(directory)) return {}
    return Object.fromEntries(readdirSync(directory)
      .filter((name) => name.endsWith('.json'))
      .sort()
      .map((name) => {
        const file = resolve(directory, name)
        return [sourceName(file), readManifest(file)]
      }))
  }
  const baseManifestModules = manifestModules(directories[1])
  if (Object.keys(baseManifestModules).length === 0) {
    throw new Error('Frontend application registry has no base manifests')
  }
  const sources: FrontendApplicationManifestSources = {
    baseManifestModules,
    contributionManifestModules: manifestModules(directories[2], true),
    sharedRoutesManifest: readManifest(resolve(registryRoot, 'shared_routes.json')),
  }
  return { sources, files, directories }
}

export function readFrontendApplicationRegistry(repositoryRoot: string) {
  const { sources, files, directories } = readFrontendApplicationManifests(repositoryRoot)
  return { registry: compileFrontendApplicationRegistry(sources), files, directories }
}
