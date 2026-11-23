#!/usr/bin/env node
import { execFileSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'

function usage() {
    console.log(`Usage: node check-translations.mjs [options]

Checks translation files changed by a PR against assets/translations/en.json.

Options:
  --root DIR       repository or worktree root (default: cwd)
  --base REV       base commit/ref (default: origin/main)
  --files LIST     comma-separated files to check instead of the PR diff
  --code           also check tr()/plural() literals in changed Dart code
  --json           print machine-readable results
  --help, -h       show this help

Exit code 1 when errors are found.
`)
}

function parseArgs(argv) {
    const opts = {
        root: process.cwd(),
        base: 'origin/main',
        files: [],
        code: false,
        json: false,
    }
    for (let i = 0; i < argv.length; i++) {
        const arg = argv[i]
        if (arg === '--root') opts.root = path.resolve(argv[++i])
        else if (arg === '--base') opts.base = String(argv[++i])
        else if (arg === '--files') {
            opts.files.push(...String(argv[++i]).split(',').map((file) => file.trim()).filter(Boolean))
        } else if (arg === '--code') opts.code = true
        else if (arg === '--json') opts.json = true
        else if (arg === '--help' || arg === '-h') {
            usage()
            process.exit(0)
        } else {
            console.error(`Unknown argument: ${arg}`)
            usage()
            process.exit(1)
        }
    }
    return opts
}

function git(root, args, { allowFail = false } = {}) {
    try {
        return execFileSync('git', ['-C', root, ...args], {
            encoding: 'utf8',
            stdio: ['ignore', 'pipe', 'pipe'],
            maxBuffer: 64 * 1024 * 1024,
        })
    } catch (e) {
        if (allowFail) return null
        throw e
    }
}

function resolveBase(root, base) {
    const candidates = [base, 'origin/main', 'main']
    for (const candidate of candidates) {
        const result = git(root, ['rev-parse', '--verify', `${candidate}^{commit}`], { allowFail: true })
        if (result && result.trim()) return candidate
    }
    throw new Error(`Could not resolve a base ref (tried ${candidates.join(', ')})`)
}

function readAtRef(root, ref, file) {
    return git(root, ['show', `${ref}:${file}`], { allowFail: true })
}

function readHead(root, file) {
    const full = path.join(root, file)
    return fs.existsSync(full) ? fs.readFileSync(full, 'utf8') : null
}

function parseJson(raw, file, errors) {
    if (raw === null) {
        errors.push({ level: 'ERROR', file, message: 'file does not exist' })
        return null
    }
    try {
        return JSON.parse(raw)
    } catch (e) {
        errors.push({ level: 'ERROR', file, message: `invalid JSON: ${e.message}` })
        return null
    }
}

function placeholders(value) {
    if (typeof value !== 'string') return []
    return [...value.matchAll(/\{[^{}]*\}/g)].map((match) => match[0]).sort()
}

function formatIssue(raw, obj) {
    if (!obj) return false
    return raw !== `${JSON.stringify(obj, null, 4)}\n`
}

function checkKeyStructure(en, local, file, errors, label = '') {
    const prefix = label ? `${label}: ` : ''
    if (typeof en === 'string' || typeof local === 'string') {
        if (typeof en !== typeof local) {
            errors.push({ level: 'ERROR', file, message: `${prefix}value type differs from en.json` })
            return
        }
    }
    if (typeof en === 'string' && typeof local === 'string') {
        const expected = placeholders(en)
        const actual = placeholders(local)
        if (JSON.stringify(expected) !== JSON.stringify(actual)) {
            errors.push({
                level: 'ERROR',
                file,
                message: `${prefix}placeholder mismatch: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
            })
        }
        return
    }
    if (en && typeof en === 'object' && local && typeof local === 'object') {
        const enKeys = Object.keys(en)
        const localKeys = Object.keys(local)
        const missing = enKeys.filter((key) => !localKeys.includes(key))
        const extra = localKeys.filter((key) => !enKeys.includes(key))
        if (missing.length) {
            errors.push({ level: 'ERROR', file, message: `${prefix}missing plural keys: ${missing.join(', ')}` })
        }
        if (extra.length) {
            errors.push({ level: 'ERROR', file, message: `${prefix}unexpected plural keys: ${extra.join(', ')}` })
        }
        for (const key of enKeys) {
            if (key in local) checkKeyStructure(en[key], local[key], file, errors, label ? `${label}.${key}` : key)
        }
    }
}

function checkFile(file, headRaw, baseRaw, enHead, enBase, errors) {
    const head = parseJson(headRaw, file, errors)
    const base = baseRaw === null ? null : parseJson(baseRaw, `${file} (base)`, errors)
    if (!head) return null

    if (formatIssue(headRaw, head)) {
        errors.push({
            level: 'ERROR',
            file,
            message: 'formatting is not four-space JSON with a final newline; run standardize.mjs',
        })
    }

    const headKeys = Object.keys(head)
    const enKeys = Object.keys(enHead)
    const missing = enKeys.filter((key) => !headKeys.includes(key))
    const extra = headKeys.filter((key) => !enKeys.includes(key))
    if (missing.length) {
        errors.push({ level: 'ERROR', file, message: `missing keys from en.json: ${missing.join(', ')}` })
    }
    if (extra.length) {
        errors.push({ level: 'ERROR', file, message: `keys not present in en.json: ${extra.join(', ')}` })
    }
    const common = headKeys.filter((key) => enKeys.includes(key))
    const expected = enKeys.filter((key) => headKeys.includes(key))
    if (common.join('\n') !== expected.join('\n')) {
        errors.push({ level: 'ERROR', file, message: 'key order does not match en.json; run standardize.mjs' })
    }

    if (base) {
        const baseKeys = Object.keys(base)
        const removed = baseKeys.filter((key) => !headKeys.includes(key))
        if (removed.length) {
            errors.push({ level: 'ERROR', file, message: `keys removed from this locale: ${removed.join(', ')}` })
        }
        for (const key of headKeys) {
            const headValue = head[key]
            const baseValue = base[key]
            if (JSON.stringify(headValue) === JSON.stringify(baseValue)) continue
            if (!enKeys.includes(key)) continue
            checkKeyStructure(enHead[key], headValue, file, errors, key)
            if (
                typeof baseValue === 'string' &&
                typeof headValue === 'string' &&
                baseValue.trim() &&
                baseValue !== enBase?.[key] &&
                enHead[key] === enBase?.[key] &&
                (headValue === enHead[key] || !headValue.trim())
            ) {
                errors.push({
                    level: 'ERROR',
                    file,
                    message: `changed value for "${key}" regressed to English or empty text`,
                })
            }
        }
    } else {
        for (const key of headKeys) {
            if (enKeys.includes(key)) checkKeyStructure(enHead[key], head[key], file, errors, key)
        }
    }
    return head
}

function changedFiles(root, base) {
    const output = git(root, ['diff', '--name-status', `${base}...HEAD`], { allowFail: true })
    if (!output) return { files: [], statuses: new Map() }
    const statuses = new Map()
    for (const line of output.split('\n')) {
        if (!line.trim()) continue
        const parts = line.split('\t')
        statuses.set(parts[parts.length - 1], parts[0])
    }
    return { files: [...statuses.keys()], statuses }
}

function checkCodeRefs(root, base, enHead, enBase, errors) {
    const dartFiles = git(root, ['diff', '--name-only', `${base}...HEAD`, '--', '*.dart'], {
        allowFail: true,
    })
    if (dartFiles && dartFiles.trim()) {
        const diff = git(root, ['diff', '-U0', `${base}...HEAD`, '--', '*.dart'], { allowFail: true })
        if (diff) {
            let currentFile = null
            for (const line of diff.split('\n')) {
                if (line.startsWith('+++ b/')) {
                    currentFile = line.slice('+++ b/'.length)
                    continue
                }
                if (!line.startsWith('+') || line.startsWith('+++') || !currentFile) continue
                if (currentFile.startsWith('test/') || currentFile.startsWith('integration_test/')) continue
                for (const match of line.matchAll(/(?:tr|plural)\(\s*['"]([^'"]+)['"]/g)) {
                    const key = match[1]
                    if (!Object.hasOwn(enHead, key)) {
                        errors.push({
                            level: 'ERROR',
                            file: currentFile,
                            message: `added tr()/plural() literal "${key}" is missing from en.json`,
                        })
                    }
                }
            }
        }
    }

    const removed = Object.keys(enBase).filter((key) => !Object.hasOwn(enHead, key))
    if (removed.length) {
        const grep = git(root, ['grep', '-h', '-E', 'tr\\(|plural\\(', 'HEAD', '--', 'lib'], {
            allowFail: true,
        })
        const refs = new Set()
        if (grep) {
            for (const match of grep.matchAll(/(?:tr|plural)\(\s*['"]([^'"]+)['"]/g)) refs.add(match[1])
        }
        for (const key of removed) {
            if (refs.has(key)) {
                errors.push({
                    level: 'ERROR',
                    file: 'assets/translations/en.json',
                    message: `removed key "${key}" is still referenced by lib/ code`,
                })
            }
        }
    }
}

function main() {
    const opts = parseArgs(process.argv.slice(2))
    if (!fs.existsSync(path.join(opts.root, 'assets', 'translations', 'en.json'))) {
        console.error(`${opts.root} does not look like the Obtainium repo root`)
        process.exit(1)
    }
    const base = resolveBase(opts.root, opts.base)
    const enHeadRaw = readHead(opts.root, 'assets/translations/en.json')
    const enBaseRaw = readAtRef(opts.root, base, 'assets/translations/en.json')
    const errors = []
    const enHead = parseJson(enHeadRaw, 'assets/translations/en.json', errors)
    const enBase = enBaseRaw === null ? null : parseJson(enBaseRaw, `assets/translations/en.json (base)`, errors)
    if (!enHead || !enBase) {
        console.error(errors.map((e) => `${e.file}: ${e.message}`).join('\n'))
        process.exit(1)
    }

    const { files, statuses } = changedFiles(opts.root, base)
    const explicit = opts.files.length > 0
    const candidates = explicit ? opts.files : files
    const translationsDir = path.join(opts.root, 'assets', 'translations')
    const localeNames = new Set(
        fs
            .readdirSync(translationsDir)
            .filter((name) => name.endsWith('.json') && !name.startsWith('package'))
            .map((name) => path.basename(name, '.json')),
    )
    const changedTranslationFiles = candidates.filter((file) => file.startsWith('assets/translations/') && file.endsWith('.json'))
    const wrongPath = candidates.filter(
        (file) =>
            !file.includes('/') &&
            file.endsWith('.json') &&
            localeNames.has(path.basename(file, '.json')),
    )
    for (const file of wrongPath) {
        errors.push({
            level: 'ERROR',
            file,
            message: 'translation file is at the repo root; it belongs in assets/translations/',
        })
    }

    const enChanged =
        files.some((file) => file === 'assets/translations/en.json') ||
        JSON.stringify(enHead) !== JSON.stringify(enBase)

    let checked = 0
    for (const file of changedTranslationFiles) {
        if (file === 'assets/translations/en.json') continue
        if (statuses.get(file) === 'D' && !explicit) {
            errors.push({ level: 'ERROR', file, message: 'translation file was deleted' })
            continue
        }
        const headRaw = readHead(opts.root, file)
        const baseRaw = readAtRef(opts.root, base, file)
        checkFile(file, headRaw, baseRaw, enHead, enBase, errors)
        checked++
    }

    if (enChanged) {
        for (const name of fs
            .readdirSync(translationsDir)
            .filter((n) => n.endsWith('.json') && n !== 'en.json' && !n.startsWith('package'))) {
            const file = path.join('assets', 'translations', name).split(path.sep).join('/')
            if (changedTranslationFiles.includes(file)) continue
            const headRaw = readHead(opts.root, file)
            const baseRaw = readAtRef(opts.root, base, file)
            checkFile(file, headRaw, baseRaw, enHead, enBase, errors)
            checked++
        }
    }

    if (opts.code) checkCodeRefs(opts.root, base, enHead, enBase, errors)

    if (!changedTranslationFiles.length && !wrongPath.length && !opts.code) {
        errors.push({
            level: 'ERROR',
            file: 'assets/translations',
            message: 'no changed translation files found',
        })
    }

    if (opts.json) {
        console.log(JSON.stringify({ base, checked, errors }, null, 2))
    } else if (errors.length) {
        for (const error of errors) {
            console.log(`${error.level} ${error.file}: ${error.message}`)
        }
        console.log(`\n${errors.length} problem(s) in ${checked} file(s), base ${base}`)
    } else {
        console.log(`PASS translations: ${checked} file(s) checked against ${base}`)
    }
    process.exit(errors.length ? 1 : 0)
}

main()
