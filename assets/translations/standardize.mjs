// Take one (hardcoded) translation file and ensure that all other translation
// files have the same keys in the same order. Reads template from en.json and
// normalises all other translation files.
//
// Before running, back up your translation files so previous translations can
// be recovered if the standardised output is wrong.

import fs from 'fs'
import path from 'path'

const main = async () => {
    const translationsDir = import.meta.dirname
    const templateFile = path.join(translationsDir, 'en.json')
    const otherFiles = fs.readdirSync(translationsDir)
        .map(f => path.join(translationsDir, f))
        .filter(f => f.endsWith('.json') && f !== templateFile && !path.basename(f).startsWith('package'))

    const templateTranslation = JSON.parse(fs.readFileSync(templateFile, 'utf-8'))

    for (const file of otherFiles) {
        const thisTranslationOriginal = JSON.parse(fs.readFileSync(file, 'utf-8'))
        const thisTranslationNew = {}
        for (const k of Object.keys(templateTranslation)) {
            thisTranslationNew[k] = thisTranslationOriginal[k] || templateTranslation[k]
        }
        const missingFromTemplate = Object.keys(thisTranslationOriginal).filter(
            k => !Object.hasOwn(templateTranslation, k),
        )
        if (missingFromTemplate.length > 0) {
            console.error(
                `${file}: keys missing from template will be dropped: ${missingFromTemplate.join(', ')}`,
            )
        }
        const tmpFile = file + '.tmp'
        fs.writeFileSync(tmpFile, `${JSON.stringify(thisTranslationNew, null, '    ')}\n`)
        fs.renameSync(tmpFile, file)
    }
}

main().catch(e => { console.error(e); process.exit(1) })
