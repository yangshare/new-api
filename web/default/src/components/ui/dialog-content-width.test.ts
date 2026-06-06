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
import assert from 'node:assert/strict'
import { readdirSync, readFileSync } from 'node:fs'
import { join, relative } from 'node:path'
import { describe, test } from 'node:test'

const sourceRoot = join(process.cwd(), 'src')

function collectTsxFiles(directory: string, files: string[] = []) {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name)

    if (entry.isDirectory()) {
      collectTsxFiles(path, files)
    } else if (entry.isFile() && path.endsWith('.tsx')) {
      files.push(path)
    }
  }

  return files
}

function getLineNumber(content: string, index: number) {
  return content.slice(0, index).split(/\r?\n/).length
}

function getClassName(tag: string) {
  const match = tag.match(
    /className\s*=\s*(?:'([^']*)'|"([^"]*)"|`([^`]*)`|\{([\s\S]*?)\})/
  )

  if (!match) return ''

  return (match[1] ?? match[2] ?? match[3] ?? match[4])
    .replace(/\s+/g, ' ')
    .trim()
}

function hasToken(className: string, pattern: RegExp) {
  return className.split(/\s+/).some((token) => pattern.test(token))
}

describe('dialog content width overrides', () => {
  test('wide DialogContent overrides use matching responsive max-width classes', () => {
    const violations: string[] = []

    for (const file of collectTsxFiles(sourceRoot)) {
      const content = readFileSync(file, 'utf8')
      const tagPattern =
        /<(DialogContent|AlertDialogContent)\b[\s\S]*?(?:\/>|>)/g
      let match: RegExpExecArray | null

      while ((match = tagPattern.exec(content)) !== null) {
        const component = match[1]
        const tag = match[0]
        const className = getClassName(tag)

        if (!className) continue

        const hasWideUnprefixedMaxWidth = hasToken(
          className,
          /^(?!max-w-sm$)max-w-(?:md|lg|xl|2xl|3xl|4xl|5xl|6xl|7xl|\[)/
        )

        if (component === 'DialogContent') {
          const hasResponsiveOverride = hasToken(
            className,
            /^(?:sm|md|lg|xl|2xl):!?max-w-/
          )
          const hasImportantOverride = hasToken(className, /^!max-w-/)

          if (
            hasWideUnprefixedMaxWidth &&
            !hasResponsiveOverride &&
            !hasImportantOverride
          ) {
            violations.push(
              `${relative(process.cwd(), file)}:${getLineNumber(content, match.index)} ${className}`
            )
          }
        }

        if (component === 'AlertDialogContent') {
          const hasCustomMaxWidth = hasToken(
            className,
            /^(?:max-w-|(?:sm|md|lg|xl|2xl):max-w-)/
          )
          const hasImportantOverride = hasToken(className, /^!max-w-/)

          if (hasCustomMaxWidth && !hasImportantOverride) {
            violations.push(
              `${relative(process.cwd(), file)}:${getLineNumber(content, match.index)} ${className}`
            )
          }
        }
      }
    }

    assert.deepEqual(violations, [])
  })
})
