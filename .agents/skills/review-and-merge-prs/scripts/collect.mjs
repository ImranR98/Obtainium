#!/usr/bin/env node
import { execFile } from 'node:child_process'
import { promisify } from 'node:util'
import fs from 'node:fs'
import path from 'node:path'

const execFileP = promisify(execFile)
const ROOT = process.cwd()
const DEFAULT_OUT = '/tmp/opencode/obtainium-pr-review/prs.json'
const STALE_DAYS = 56
const BODY_LIMIT = 8000

const PR_FIELDS = [
    'number',
    'title',
    'author',
    'isDraft',
    'createdAt',
    'updatedAt',
    'baseRefName',
    'headRefName',
    'headRefOid',
    'headRepository',
    'headRepositoryOwner',
    'isCrossRepository',
    'maintainerCanModify',
    'mergeable',
    'mergeStateStatus',
    'reviewDecision',
    'labels',
    'additions',
    'deletions',
    'changedFiles',
    'body',
    'closingIssuesReferences',
    'statusCheckRollup',
    'commits',
    'state',
    'url',
    'mergedAt',
    'closedAt',
    'autoMergeRequest',
].join(',')

function usage() {
    console.log(`Usage: node collect.mjs prs [options]

Collects raw PR facts and writes a JSON file, a grep-friendly digest, and per-PR diffs.
It computes no verdicts; read references/criteria.md and judge yourself.

Options:
  --pr N              include a specific PR (repeatable)
  --prs N,N           include comma-separated PRs
  --author LOGIN      only open PRs by this author
  --limit N           max open PRs to collect (default 100)
  --skip-diff         skip full diffs (faster, fewer flags)
  --skip-comments     skip comment/review metadata
  --out PATH          JSON file or output directory (default ${DEFAULT_OUT})
  --print-digest      print the digest after writing
  --help, -h          show this help

Outputs:
  <out>                       JSON facts
  <out>.digest.txt            one block per PR
  <dir>/diffs/<n>.diff        full PR diffs unless --skip-diff
`)
}

function parseArgs(argv) {
    if (argv[0] !== 'prs') {
        usage()
        process.exit(argv[0] === '--help' || argv[0] === '-h' ? 0 : 1)
    }
    const opts = {
        prs: [],
        author: null,
        limit: 100,
        skipDiff: false,
        skipComments: false,
        out: DEFAULT_OUT,
        printDigest: false,
    }
    for (let i = 1; i < argv.length; i++) {
        const arg = argv[i]
        if (arg === '--pr') opts.prs.push(Number(argv[++i]))
        else if (arg === '--prs') opts.prs.push(...String(argv[++i]).split(',').map(Number))
        else if (arg === '--author') opts.author = String(argv[++i]).toLowerCase()
        else if (arg === '--limit') opts.limit = Math.max(1, Number(argv[++i]) || 100)
        else if (arg === '--skip-diff') opts.skipDiff = true
        else if (arg === '--skip-comments') opts.skipComments = true
        else if (arg === '--out') opts.out = String(argv[++i])
        else if (arg === '--print-digest') opts.printDigest = true
        else if (arg === '--help' || arg === '-h') {
            usage()
            process.exit(0)
        } else {
            console.error(`Unknown argument: ${arg}`)
            usage()
            process.exit(1)
        }
    }
    opts.prs = [...new Set(opts.prs.filter((n) => Number.isInteger(n) && n > 0))]
    if (opts.out.endsWith('.json')) {
        opts.outFile = path.resolve(opts.out)
    } else {
        opts.outFile = path.resolve(opts.out, 'prs.json')
    }
    return opts
}

async function runGh(args, { allowFail = false } = {}) {
    try {
        const { stdout, stderr } = await execFileP('gh', args, {
            cwd: ROOT,
            encoding: 'utf8',
            maxBuffer: 256 * 1024 * 1024,
        })
        return { ok: true, stdout, stderr }
    } catch (e) {
        const result = {
            ok: false,
            stdout: e.stdout || '',
            stderr: e.stderr || e.message || String(e),
        }
        if (allowFail) return result
        throw new Error(`gh ${args.join(' ')} failed: ${result.stderr.trim().split('\n')[0]}`)
    }
}

async function ghJson(args, opts) {
    const result = await runGh(args, opts)
    if (!result.stdout.trim()) return null
    return JSON.parse(result.stdout)
}

async function ghApi(endpoint, { allowFail = false } = {}) {
    return ghJson(['api', endpoint], { allowFail })
}

async function ghApiPaged(endpoint) {
    const out = []
    for (let page = 1; page <= 20; page++) {
        const sep = endpoint.includes('?') ? '&' : '?'
        const pageItems = await ghApi(`${endpoint}${sep}per_page=100&page=${page}`)
        if (!Array.isArray(pageItems)) throw new Error(`Expected array from ${endpoint}`)
        out.push(...pageItems)
        if (pageItems.length < 100) break
    }
    return out
}

async function detectRepo() {
    const result = await runGh(['repo', 'view', '--json', 'nameWithOwner', '-q', '.nameWithOwner'])
    return result.stdout.trim()
}

function splitRepo(repo) {
    const [owner, name] = repo.split('/')
    return { owner, name }
}

function mapLimit(items, limit, fn) {
    const results = new Array(items.length)
    let next = 0
    const workers = Array.from({ length: Math.min(limit, items.length) || 1 }, async () => {
        for (;;) {
            const index = next++
            if (index >= items.length) return
            results[index] = await fn(items[index], index)
        }
    })
    return Promise.all(workers).then(() => results)
}

function daysSince(iso) {
    if (!iso) return null
    return Math.floor((Date.now() - new Date(iso).getTime()) / 86400000)
}

function fileScope(file) {
    if (file.startsWith('assets/translations/')) return 'translations'
    if (file.startsWith('lib/')) return 'lib'
    if (file.startsWith('test/')) return 'test'
    if (file.startsWith('integration_test/')) return 'integration_test'
    if (file.startsWith('android/')) return 'android'
    if (file.startsWith('packages/')) return 'packages'
    if (file.startsWith('docs/')) return 'docs'
    if (file.startsWith('.github/')) return 'ci'
    if (['README.md', 'AGENTS.md'].includes(file)) return 'docs'
    if (file.startsWith('fastlane/') || file.startsWith('tool/')) return 'tooling'
    return 'other'
}

function isRootFile(file) {
    return !file.includes('/')
}

const ROOT_ALLOW = new Set([
    'AGENTS.md',
    'analysis_options.yaml',
    'build.sh',
    'devtools_options.yaml',
    'LICENSE.txt',
    'obtainium.iml',
    'pubspec.lock',
    'pubspec.yaml',
    'README.md',
    'sign.sh',
    '.gitignore',
    '.gitmodules',
    '.metadata',
])

const GENERATED_PREFIXES = ['build/', 'data/', '.dart_tool/', 'coverage/', 'dist/', '.flutter/']
const SECRET_NAMES = [
    'key.properties',
    'google-services.json',
    'google-services.json.example',
    '.env',
]
const SECRET_EXTENSIONS = ['.jks', '.keystore', '.p12', '.pem', '.key', '.mobileprovision']
const SENSITIVE_PATHS = [
    /^lib\/installers\//,
    /^lib\/providers\/source_provider\.dart$/,
    /^lib\/providers\/app_json_migration\.dart$/,
    /^lib\/providers\/apps_provider_import_export\.dart$/,
    /^lib\/pages\/import_export\.dart$/,
    /^lib\/pages\/home\.dart$/,
    /^lib\/main\.dart$/,
    /^lib\/app_sources\//,
    /^lib\/providers\/apps_provider(_.*)?\.dart$/,
    /^android\/app\/src\/main\/AndroidManifest\.xml$/,
]

function isSensitive(file) {
    return SENSITIVE_PATHS.some((re) => re.test(file))
}

function diffSection(diff, file) {
    if (!diff) return null
    const marker = `diff --git a/${file} b/${file}`
    const start = diff.indexOf(marker)
    if (start < 0) return null
    const next = diff.indexOf('\ndiff --git ', start + marker.length)
    return diff.slice(start, next < 0 ? diff.length : next)
}

function parseDiffFlags(diff, files) {
    const flags = new Set()
    if (!diff) {
        flags.add('diff-skipped')
        return flags
    }

    const pubspec = diffSection(diff, 'pubspec.yaml')
    if (pubspec) {
        const removed = [...pubspec.matchAll(/^-version:\s*(\S+)\s*$/gm)].map((m) => m[1])
        const added = [...pubspec.matchAll(/^\+version:\s*(\S+)\s*$/gm)].map((m) => m[1])
        if (added.length && JSON.stringify(removed) !== JSON.stringify(added)) {
            flags.add('version-bump')
        }
        const addedKeys = [...pubspec.matchAll(/^\+ {2}([A-Za-z0-9_]+):/gm)].map((m) => m[1])
        const metadata = new Set([
            'name',
            'description',
            'publish_to',
            'version',
            'environment',
            'flutter',
            'homepage',
            'repository',
            'issue_tracker',
        ])
        if (addedKeys.some((key) => !metadata.has(key))) flags.add('new-dep')
    }

    if (/BEGIN [A-Z ]*PRIVATE KEY/.test(diff)) flags.add('secret')
    if (/^Binary files .* differ$/m.test(diff)) flags.add('binary')

    for (const file of files) {
        if (GENERATED_PREFIXES.some((prefix) => file.startsWith(prefix))) flags.add('generated')
        if (/\.(g|freezed|mocks?)\.dart$/.test(file)) flags.add('generated')
        if (SECRET_NAMES.includes(path.basename(file))) flags.add('secret')
        if (SECRET_EXTENSIONS.includes(path.extname(file).toLowerCase())) flags.add('secret')
        if (isRootFile(file) && !ROOT_ALLOW.has(file)) flags.add('root-file')
    }
    return flags
}

function checkSummary(rollup) {
    const items = Array.isArray(rollup) ? rollup : []
    if (!items.length) return { state: 'none', failed: [], pending: [] }
    const failedStates = new Set([
        'FAILURE',
        'CANCELLED',
        'TIMED_OUT',
        'ACTION_REQUIRED',
        'STARTUP_FAILURE',
        'ERROR',
    ])
    const pendingStates = new Set(['QUEUED', 'IN_PROGRESS', 'PENDING', 'WAITING', 'REQUESTED'])
    const failed = []
    const pending = []
    for (const item of items) {
        const name = item.name || item.context || item.checkSuite?.app?.name || 'check'
        const state = String(item.conclusion || item.state || item.status || '').toUpperCase()
        if (failedStates.has(state)) failed.push(name)
        else if (pendingStates.has(state)) pending.push(name)
    }
    if (failed.length) return { state: 'failed', failed, pending }
    if (pending.length) return { state: 'pending', failed, pending }
    return { state: 'passed', failed, pending }
}

function extractMentions(text, ownNumber) {
    const found = new Set()
    for (const match of String(text || '').matchAll(/(?:^|[^A-Za-z0-9_])#(\d+)/g)) {
        const number = Number(match[1])
        if (number && number !== ownNumber) found.add(number)
    }
    return [...found].slice(0, 12)
}

function buildScopes(files) {
    const scopes = new Set()
    for (const file of files) scopes.add(fileScope(file))
    return [...scopes].sort()
}

function summarizeFiles(files) {
    const counts = {}
    for (const file of files) {
        const scope = fileScope(file)
        counts[scope] = (counts[scope] || 0) + 1
    }
    return Object.keys(counts).sort().map((key) => `${key}=${counts[key]}`).join(' ')
}

function digestFor(pr, repo) {
    const linked = []
    for (const ref of pr.issues.closing) linked.push(`#${ref.number}(${ref.state})`)
    for (const ref of pr.issues.mentions) {
        if (!pr.issues.closing.some((c) => c.number === ref.number)) {
            linked.push(`~#${ref.number}(${ref.state}${ref.isPullRequest ? ',PR' : ''})`)
        }
    }
    const flags = pr.flags.filter((flag) => flag !== 'diff-skipped' || pr.diffPath === null)
    const first = [
        `#${pr.number}`,
        pr.kind,
        `@${pr.author.login}`,
        `draft=${pr.isDraft ? 'yes' : 'no'}`,
        `${pr.mergeable || 'UNKNOWN'}/${pr.mergeStateStatus || 'UNKNOWN'}`,
        `base=${pr.baseRefName}`,
        `+${pr.additions}/-${pr.deletions}`,
        `${pr.files.length}f`,
        `checks=${pr.checks.state}${pr.checks.failed.length ? ':' + pr.checks.failed.join('|') : ''}`,
        linked.length ? `linked=${linked.join(',')}` : null,
        `updated=${pr.updatedAt ? pr.updatedAt.slice(0, 10) : 'unknown'}(${pr.updatedDays ?? '?'}d)`,
        flags.length ? `flags=${flags.join(',')}` : null,
        pr.title,
    ].filter(Boolean)
    const lines = [first.join(' | ')]
    if (pr.files.length) lines.push(`  files: ${summarizeFiles(pr.files)}`)
    const locales = pr.files
        .filter((file) => file.startsWith('assets/translations/'))
        .map((file) => path.basename(file, '.json'))
    if (locales.length && locales.length <= 40) lines.push(`  locales: ${locales.join(',')}`)
    const paths = pr.files.filter((file) => !file.startsWith('assets/translations/')).map((file) => file)
    if (paths.length) {
        const shown = paths.slice(0, 24)
        lines.push(`  paths: ${shown.join(', ')}${paths.length > shown.length ? `, +${paths.length - shown.length} more` : ''}`)
    }
    return lines
}

function buildOverlaps(prs) {
    const fileMap = new Map()
    const issueMap = new Map()
    for (const pr of prs) {
        for (const file of pr.files) {
            if (['pubspec.lock', 'pubspec.yaml'].includes(file)) continue
            if (!fileMap.has(file)) fileMap.set(file, new Set())
            fileMap.get(file).add(pr.number)
        }
        for (const ref of pr.issues.closing) {
            if (!issueMap.has(ref.number)) issueMap.set(ref.number, new Set())
            issueMap.get(ref.number).add(pr.number)
        }
    }
    const files = [...fileMap.entries()]
        .filter(([, numbers]) => numbers.size > 1)
        .map(([file, numbers]) => ({ file, prs: [...numbers].sort((a, b) => a - b) }))
    const issues = [...issueMap.entries()]
        .filter(([, numbers]) => numbers.size > 1)
        .map(([issue, numbers]) => ({ issue, prs: [...numbers].sort((a, b) => a - b) }))
    return { files, issues }
}

function prList(numbers, max = 8) {
    const shown = numbers.slice(0, max).map((number) => '#' + number)
    return `${shown.join(',')}${numbers.length > shown.length ? `,+${numbers.length - shown.length}` : ''}`
}

function applyOverlapFlags(prs, overlaps) {
    const fileOverlapByPr = new Map()
    const issueOverlapByPr = new Map()
    for (const group of overlaps.files) {
        for (const number of group.prs) {
            if (!fileOverlapByPr.has(number)) fileOverlapByPr.set(number, new Set())
            for (const other of group.prs) {
                if (other !== number) fileOverlapByPr.get(number).add(other)
            }
            const pr = prs.find((candidate) => candidate.number === number)
            if (pr) pr.overlapFiles.push(group.file)
        }
    }
    for (const group of overlaps.issues) {
        for (const number of group.prs) {
            if (!issueOverlapByPr.has(number)) issueOverlapByPr.set(number, new Set())
            for (const other of group.prs) {
                if (other !== number) issueOverlapByPr.get(number).add(other)
            }
        }
    }
    for (const pr of prs) {
        const files = [...(fileOverlapByPr.get(pr.number) || [])].sort((a, b) => a - b)
        const issues = [...(issueOverlapByPr.get(pr.number) || [])].sort((a, b) => a - b)
        if (files.length) pr.flags.add(`same-file:${prList(files)}`)
        if (issues.length) pr.flags.add(`same-issue:${prList(issues)}`)
    }
}

async function fetchIssue(repo, number, cache) {
    if (cache.has(number)) return cache.get(number)
    const result = await ghApi(`repos/${repo}/issues/${number}`, { allowFail: true })
    let value
    if (result && typeof result === 'object') {
        value = {
            number,
            title: result.title || null,
            state: result.state || 'unknown',
            isPullRequest: !!result.pull_request,
            closedAt: result.closed_at || null,
        }
    } else {
        value = { number, title: null, state: 'unknown', isPullRequest: false, closedAt: null }
    }
    cache.set(number, value)
    return value
}

async function fetchComments(repo, number) {
    const result = await ghApi(`repos/${repo}/issues/${number}/comments?per_page=100`, { allowFail: true })
    if (Array.isArray(result)) return result
    const prResult = await ghApi(`repos/${repo}/pulls/${number}/comments?per_page=100`, { allowFail: true })
    return Array.isArray(prResult) ? prResult : []
}

async function fetchReviews(repo, number) {
    const result = await ghApi(`repos/${repo}/pulls/${number}/reviews?per_page=100`, { allowFail: true })
    return Array.isArray(result) ? result : []
}

function normalizeCommit(commit) {
    return {
        oid: commit.oid || commit.commit?.oid || null,
        headline: commit.messageHeadline || commit.commit?.messageHeadline || null,
        author: commit.authors?.[0]?.login || commit.author?.login || commit.commit?.author?.name || null,
        date: commit.committedDate || commit.commit?.author?.date || null,
    }
}

async function collectPr(repo, base, opts, issueCache) {
    const pr = { ...base }
    const files = await ghApiPaged(`repos/${repo}/pulls/${pr.number}/files`)
    const changedFiles = files.map((file) => file.filename)
    pr.files = changedFiles
    pr.fileDetails = files.map((file) => ({
        path: file.filename,
        status: file.status,
        additions: file.additions,
        deletions: file.deletions,
        changes: file.changes,
        previousPath: file.previous_filename || null,
    }))
    pr.commits = (pr.commits || []).map(normalizeCommit)

    let diff = null
    pr.diffPath = null
    if (!opts.skipDiff) {
        const diffResult = await runGh(['pr', 'diff', String(pr.number), '--repo', repo], { allowFail: true })
        if (diffResult.ok) {
            diff = diffResult.stdout
            pr.diffPath = path.join(opts.diffDir, `${pr.number}.diff`)
            fs.writeFileSync(pr.diffPath, diff)
        } else {
            pr.diffError = diffResult.stderr.trim().split('\n')[0] || 'diff failed'
        }
    }

    pr.flags = parseDiffFlags(diff, changedFiles)
    pr.scopes = buildScopes(changedFiles)
    pr.overlapFiles = []
    pr.checks = checkSummary(pr.statusCheckRollup)
    pr.updatedDays = daysSince(pr.updatedAt)
    pr.createdDays = daysSince(pr.createdAt)

    if (pr.isDraft) pr.flags.add('draft')
    if (pr.mergeable === 'CONFLICTING' || pr.mergeStateStatus === 'DIRTY') pr.flags.add('conflict')
    if (pr.mergeStateStatus === 'BEHIND') pr.flags.add('behind')
    if (pr.baseRefName !== 'main') pr.flags.add('base-not-main')
    if (pr.updatedDays !== null && pr.updatedDays > STALE_DAYS) {
        pr.flags.add('stale')
        if (pr.isDraft) pr.flags.add('stale-draft')
    }
    if (!pr.body || !String(pr.body).trim()) pr.flags.add('no-body')
    if (pr.isCrossRepository) pr.flags.add('fork')
    if (!pr.maintainerCanModify) pr.flags.add('no-maintainer-edit')
    if (pr.checks.state === 'failed') pr.flags.add('checks-failed')
    if (pr.checks.state === 'pending') pr.flags.add('checks-pending')

    const codeFiles = changedFiles.filter((file) =>
        ['lib', 'test', 'integration_test', 'android', 'packages'].includes(fileScope(file)),
    )
    const sourceFiles = changedFiles.filter((file) => file.startsWith('lib/app_sources/'))
    const testFiles = changedFiles.filter(
        (file) => file.startsWith('test/') || file.startsWith('integration_test/'),
    )
    const docsFiles = changedFiles.filter(
        (file) => file.startsWith('docs/') || file === 'README.md' || file === 'AGENTS.md',
    )
    if (sourceFiles.length) {
        pr.flags.add('source-change')
        if (files.some((file) => file.status === 'added' && file.filename.startsWith('lib/app_sources/'))) {
            pr.flags.add('new-source')
        }
    }
    if (codeFiles.length && !testFiles.length) pr.flags.add('tests-missing')
    if (codeFiles.length && !docsFiles.length) pr.flags.add('docs-missing')
    if (changedFiles.some((file) => file.startsWith('android/'))) pr.flags.add('android')
    if (changedFiles.some((file) => file.startsWith('packages/'))) pr.flags.add('native')
    if (changedFiles.some((file) => file.startsWith('assets/translations/en.json'))) {
        pr.flags.add('en-changed')
    } else if (
        changedFiles.some((file) => file.startsWith('assets/translations/')) &&
        !codeFiles.length
    ) {
        pr.flags.add('locale-only')
    }
    if (changedFiles.some(isSensitive)) pr.flags.add('sensitive')
    if (changedFiles.some((file) => file === 'pubspec.yaml')) pr.flags.add('pubspec-changed')
    if (changedFiles.some((file) => file === 'pubspec.lock')) pr.flags.add('lock-changed')
    if (changedFiles.some((file) => file === '.flutter' || file.startsWith('.flutter/'))) {
        pr.flags.add('flutter-pointer')
    }

    const closingRefs = (pr.closingIssuesReferences || []).map((ref) => ref.number)
    const mentionRefs = extractMentions(`${pr.title}\n${pr.body || ''}`, pr.number)
    const allRefs = [...new Set([...closingRefs, ...mentionRefs])]
    const issueFacts = await mapLimit(allRefs, 4, (number) => fetchIssue(repo, number, issueCache))
    const issueByNumber = new Map(issueFacts.map((fact) => [fact.number, fact]))
    pr.issues = {
        closing: closingRefs.map((number) => issueByNumber.get(number)).filter(Boolean),
        mentions: mentionRefs.map((number) => issueByNumber.get(number)).filter(Boolean),
    }
    if (pr.issues.closing.some((issue) => issue.state === 'closed')) {
        pr.flags.add('linked-closed')
    }
    if (pr.issues.mentions.some((issue) => issue.isPullRequest)) pr.flags.add('mentions-pr')

    if (opts.skipComments) {
        pr.comments = []
        pr.reviews = []
        pr.lastComment = null
        pr.lastReview = null
    } else {
        const comments = await fetchComments(repo, pr.number)
        const reviews = await fetchReviews(repo, pr.number)
        pr.comments = comments.map((comment) => ({
            author: comment.user?.login || null,
            at: comment.created_at || null,
            body: String(comment.body || '').slice(0, 240),
        }))
        pr.reviews = reviews.map((review) => ({
            author: review.user?.login || null,
            state: review.state || null,
            at: review.submitted_at || null,
            body: String(review.body || '').slice(0, 240),
        }))
        pr.lastComment = pr.comments.length ? pr.comments[pr.comments.length - 1] : null
        pr.lastReview = pr.reviews.length ? pr.reviews[pr.reviews.length - 1] : null
        const owner = splitRepo(repo).owner
        const maintainerComments = pr.comments.filter((comment) => comment.author === owner)
        pr.lastMaintainerComment = maintainerComments.length
            ? maintainerComments[maintainerComments.length - 1]
            : null
    }

    pr.body = String(pr.body || '').slice(0, BODY_LIMIT)
    pr.bodyTruncated = String(base.body || '').length > BODY_LIMIT
    pr.kind =
        pr.author.login === splitRepo(repo).owner
            ? 'internal'
            : pr.files.length === 0
              ? 'empty'
              : pr.files.every((file) => file.startsWith('assets/translations/'))
                ? 'translations'
                : pr.files.every(
                        (file) =>
                            file.startsWith('docs/') ||
                            file === 'README.md' ||
                            file === 'AGENTS.md',
                    )
                  ? 'docs'
                  : codeFiles.length
                    ? 'code'
                    : 'mixed'

    return pr
}

async function main() {
    const opts = parseArgs(process.argv.slice(2))
    const repo = await detectRepo()
    const outFile = opts.outFile
    const diffDir = path.join(path.dirname(outFile), 'diffs')
    opts.diffDir = diffDir
    fs.mkdirSync(path.dirname(outFile), { recursive: true })
    fs.rmSync(diffDir, { recursive: true, force: true })
    fs.mkdirSync(diffDir, { recursive: true })

    let bases = []
    if (opts.prs.length) {
        bases = await mapLimit(opts.prs, 4, async (number) => {
            const pr = await ghJson(['pr', 'view', String(number), '--repo', repo, '--json', PR_FIELDS])
            if (!pr) throw new Error(`PR #${number} not found`)
            return pr
        })
    } else {
        const list = await ghJson([
            'pr',
            'list',
            '--repo',
            repo,
            '--state',
            'open',
            '--limit',
            String(opts.limit),
            '--json',
            PR_FIELDS,
        ])
        bases = Array.isArray(list) ? list : []
        if (opts.author) {
            bases = bases.filter((pr) => String(pr.author?.login || '').toLowerCase() === opts.author)
        }
        if (bases.length > opts.limit) bases = bases.slice(0, opts.limit)
    }

    const issueCache = new Map()
    const prs = await mapLimit(bases, 4, (pr) => collectPr(repo, pr, opts, issueCache))
    const overlaps = buildOverlaps(prs)
    applyOverlapFlags(prs, overlaps)
    for (const pr of prs) pr.flags = [...new Set(pr.flags)].sort()

    prs.sort((a, b) => a.number - b.number)
    const payload = {
        generatedAt: new Date().toISOString(),
        repo,
        outFile,
        diffDir,
        staleDays: STALE_DAYS,
        counts: {
            collected: prs.length,
            byKind: Object.fromEntries(
                [...new Set(prs.map((pr) => pr.kind))].sort().map((kind) => [
                    kind,
                    prs.filter((pr) => pr.kind === kind).length,
                ]),
            ),
        },
        overlaps,
        prs,
    }
    fs.writeFileSync(outFile, `${JSON.stringify(payload, null, 2)}\n`)

    const digestLines = [
        '# Obtainium PR review facts',
        `repo=${repo} | generated=${payload.generatedAt} | collected=${prs.length}`,
        `json=${outFile}`,
        `diffs=${diffDir}`,
        `counts=${JSON.stringify(payload.counts.byKind)}`,
    ]
    if (overlaps.files.length) {
        digestLines.push('')
        digestLines.push('overlap.files:')
        for (const group of overlaps.files) {
            digestLines.push(`  ${group.file} -> ${group.prs.map((n) => '#' + n).join(',')}`)
        }
    }
    if (overlaps.issues.length) {
        digestLines.push('')
        digestLines.push('overlap.issues:')
        for (const group of overlaps.issues) {
            digestLines.push(`  #${group.issue} -> ${group.prs.map((n) => '#' + n).join(',')}`)
        }
    }
    for (const pr of prs) {
        digestLines.push('')
        digestLines.push(...digestFor(pr, repo))
    }
    const digest = `${digestLines.join('\n')}\n`
    const digestFile = `${outFile}.digest.txt`
    fs.writeFileSync(digestFile, digest)

    console.log(`Wrote ${outFile}`)
    console.log(`Wrote ${digestFile}`)
    console.log(`Wrote ${diffDir}`)
    console.log(`Collected ${prs.length} PR(s), ${payload.counts.byKind ? JSON.stringify(payload.counts.byKind) : ''}`)
    if (opts.printDigest) process.stdout.write(`\n${digest}`)
}

main().catch((e) => {
    console.error(e.stack || e.message || String(e))
    process.exit(1)
})
