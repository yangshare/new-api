/*
Copyright (C) 2023-2026 QuantumNous

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program. If not, see <https://www.gnu.org/licenses/>.

For commercial licensing, please contact support@quantumnous.com
*/
import { spawnSync } from 'node:child_process'
import { existsSync, statSync } from 'node:fs'
import { extname } from 'node:path'

const root = process.cwd()
const args = process.argv.slice(2)
const fix = args.includes('--fix')
const extensions = new Set([
  '.cjs',
  '.cts',
  '.js',
  '.jsx',
  '.mjs',
  '.mts',
  '.ts',
  '.tsx',
])
const excludedSegments = new Set([
  '.git',
  '.tanstack',
  'build',
  'coverage',
  'dist',
  'node_modules',
])
const maxFileSize = 10 * 1024 * 1024

function gitLines(args) {
  const result = spawnSync('git', args, {
    cwd: root,
    encoding: 'utf8',
  })

  if (result.status !== 0) {
    return []
  }

  return result.stdout.split(/\r?\n/).filter(Boolean)
}

function gitRefExists(ref) {
  const result = spawnSync('git', ['rev-parse', '--verify', ref], {
    cwd: root,
    stdio: 'ignore',
  })

  return result.status === 0
}

function addGitFiles(files, args) {
  for (const file of gitLines(args)) {
    files.add(file)
  }
}

function isLintable(file) {
  const normalized = file.replaceAll('\\', '/')
  const segments = normalized.split('/')

  if (segments.some((segment) => excludedSegments.has(segment))) {
    return false
  }

  if (
    normalized.startsWith('src/components/ui/') ||
    normalized === 'src/routeTree.gen.ts'
  ) {
    return false
  }

  if (!extensions.has(extname(normalized))) {
    return false
  }

  if (!existsSync(file)) {
    return false
  }

  const stats = statSync(file)
  return stats.isFile() && stats.size < maxFileSize
}

const files = new Set()
const base = process.env.LINT_BASE || process.env.CHECK_BASE || 'origin/dev'

if (base && gitRefExists(base)) {
  addGitFiles(files, [
    'diff',
    '--name-only',
    '--relative',
    '--diff-filter=ACMR',
    `${base}...HEAD`,
    '--',
    '.',
  ])
}

addGitFiles(files, [
  'diff',
  '--name-only',
  '--relative',
  '--diff-filter=ACMR',
  '--',
  '.',
])
addGitFiles(files, [
  'diff',
  '--cached',
  '--name-only',
  '--relative',
  '--diff-filter=ACMR',
  '--',
  '.',
])
addGitFiles(files, ['ls-files', '--others', '--exclude-standard', '--', '.'])

const lintFiles = [...files].filter(isLintable).sort()

if (lintFiles.length === 0) {
  console.log('lint: no changed JS/TS files')
  process.exit(0)
}

const oxlintArgs = ['-c', '.oxlintrc.json', ...lintFiles]
if (fix) {
  oxlintArgs.push('--fix')
}

const result = spawnSync('oxlint', oxlintArgs, {
  cwd: root,
  stdio: 'inherit',
})

if (result.error) {
  console.error(`lint: failed to run oxlint: ${result.error.message}`)
  process.exit(1)
}

process.exit(result.status ?? 1)
