import { cpSync, existsSync, mkdirSync, rmSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const docsRoot = fileURLToPath(new URL('..', import.meta.url))
const source = join(docsRoot, 'dist')
const destination = join(docsRoot, '..', 'public', 'docs')

if (!existsSync(source)) {
  throw new Error('Documentation output is missing. Run the documentation build first.')
}

rmSync(destination, { recursive: true, force: true })
mkdirSync(dirname(destination), { recursive: true })
cpSync(source, destination, { recursive: true })

console.log(`Published documentation to ${destination}`)
