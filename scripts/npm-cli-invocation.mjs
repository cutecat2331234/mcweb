import { realpathSync, statSync } from 'node:fs'
import { basename, isAbsolute } from 'node:path'
import process from 'node:process'

function canonicalFilePath(label, candidate) {
  if (typeof candidate !== 'string' || candidate.length === 0) {
    throw new Error(
      `${label} is required; launch the E2E suite through an npm script`,
    )
  }
  if (!isAbsolute(candidate)) {
    throw new Error(`${label} must be an absolute path`)
  }

  let canonical
  try {
    canonical = realpathSync.native(candidate)
  } catch {
    throw new Error(`${label} must reference an existing file`)
  }
  if (!statSync(canonical).isFile()) {
    throw new Error(`${label} must reference a file`)
  }
  return canonical
}

function pathsMatch(left, right, platform) {
  if (platform === 'win32') {
    return left.toLocaleLowerCase('en-US') === right.toLocaleLowerCase('en-US')
  }
  return left === right
}

export function resolveNpmCliInvocation(
  args,
  {
    environment = process.env,
    currentNodePath = process.execPath,
    platform = process.platform,
  } = {},
) {
  if (
    !Array.isArray(args) ||
    args.some((argument) => typeof argument !== 'string')
  ) {
    throw new TypeError('npm arguments must be an array of strings')
  }

  const npmCliPath = canonicalFilePath('npm_execpath', environment.npm_execpath)
  if (basename(npmCliPath).toLocaleLowerCase('en-US') !== 'npm-cli.js') {
    throw new Error('npm_execpath must reference npm-cli.js')
  }

  const declaredNodePath = canonicalFilePath(
    'npm_node_execpath',
    environment.npm_node_execpath,
  )
  const activeNodePath = canonicalFilePath('process.execPath', currentNodePath)
  if (!pathsMatch(declaredNodePath, activeNodePath, platform)) {
    throw new Error(
      'npm_node_execpath must identify the active Node.js executable',
    )
  }

  return {
    executable: currentNodePath,
    args: [npmCliPath, ...args],
  }
}

export function resolveSpawnInvocation(executable, args, options) {
  if (executable === 'npm' || executable === 'npm.cmd') {
    return resolveNpmCliInvocation(args, options)
  }
  return { executable, args }
}
