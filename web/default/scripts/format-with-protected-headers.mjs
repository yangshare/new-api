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
import {
  existsSync,
  readdirSync,
  readFileSync,
  statSync,
  writeFileSync,
} from 'node:fs'
import { join, relative } from 'node:path'

const args = new Set(process.argv.slice(2))
const hasCheck = args.has('--check')
const hasWrite = args.has('--write')
const includeAll = args.has('--all')

if (hasCheck === hasWrite) {
  console.error(
    'Usage: node scripts/format-with-protected-headers.mjs --check|--write [--all]'
  )
  process.exit(2)
}

const mode = hasCheck ? '--check' : '--write'
const root = process.cwd()
const maxFileSize = 10 * 1024 * 1024
const excludedDirs = new Set([
  '.git',
  '.tanstack',
  'build',
  'coverage',
  'dist',
  'node_modules',
])
const headerExtensions = new Set([
  '.cjs',
  '.cts',
  '.js',
  '.jsx',
  '.mjs',
  '.mts',
  '.ts',
  '.tsx',
])
const protectedHeaderPattern =
  /^\/\*\nCopyright \(C\)[\s\S]*?QuantumNous[\s\S]*?\*\/\n+/

function extensionOf(path) {
  const index = path.lastIndexOf('.')
  return index === -1 ? '' : path.slice(index)
}

function walk(dir, files = []) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      if (!excludedDirs.has(entry.name)) {
        walk(join(dir, entry.name), files)
      }
      continue
    }

    if (entry.isFile()) {
      files.push(join(dir, entry.name))
    }
  }

  return files
}

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
    files.add(join(root, file))
  }
}

function collectChangedFiles() {
  const files = new Set()
  const base = process.env.FORMAT_BASE || process.env.CHECK_BASE || 'origin/dev'

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

  return [...files]
}

function isFormattableCandidate(file) {
  if (!existsSync(file)) {
    return false
  }

  const stats = statSync(file)
  return stats.isFile() && stats.size < maxFileSize
}

function snapshotFiles(files) {
  const snapshot = new Map()
  for (const file of files) {
    snapshot.set(file, readFileSync(file))
  }
  return snapshot
}

function restoreSnapshot(snapshot) {
  for (const [file, content] of snapshot) {
    writeFileSync(file, content)
  }
}

function stripProtectedHeaders(files) {
  const headers = new Map()

  for (const file of files) {
    if (!headerExtensions.has(extensionOf(file))) {
      continue
    }

    const content = readFileSync(file, 'utf8')
    const match = content.match(protectedHeaderPattern)
    if (!match) {
      continue
    }

    headers.set(file, match[0])
    writeFileSync(file, content.slice(match[0].length))
  }

  return headers
}

function restoreProtectedHeaders(headers) {
  for (const [file, header] of headers) {
    const content = readFileSync(file, 'utf8').replace(/^\n+/, '')
    if (!content.startsWith(header)) {
      writeFileSync(file, header + content)
    }
  }
}

function listChangedFiles(before, files) {
  const changed = []

  for (const file of files) {
    const previous = before.get(file)
    const current = readFileSync(file)
    if (!previous || !previous.equals(current)) {
      changed.push(relative(root, file))
    }
  }

  return changed
}

const files = (includeAll ? walk(root) : collectChangedFiles()).filter(
  isFormattableCandidate
)

if (files.length === 0) {
  console.log(
    mode === '--check'
      ? 'format: no changed files to check'
      : 'format: no changed files'
  )
  process.exit(0)
}

const before = mode === '--check' ? snapshotFiles(files) : null
let headers = new Map()
let exitCode = 0

try {
  headers = stripProtectedHeaders(files)
  const targets = includeAll ? ['.'] : files.map((file) => relative(root, file))
  const result = spawnSync(
    'oxfmt',
    [
      '-c',
      '.oxfmtrc.json',
      '--ignore-path',
      '.gitignore',
      '--write',
      ...targets,
    ],
    {
      cwd: root,
      stdio: 'inherit',
    }
  )
  exitCode = result.status ?? 1
  restoreProtectedHeaders(headers)

  if (mode === '--check' && exitCode === 0) {
    const changed = listChangedFiles(before, files)
    if (changed.length > 0) {
      console.error('Format issues found in protected-header-safe check:')
      for (const file of changed) {
        console.error(file)
      }
      exitCode = 1
    }
  }
} finally {
  if (mode === '--check' && before) {
    restoreSnapshot(before)
  } else {
    restoreProtectedHeaders(headers)
  }
}

process.exit(exitCode)
