// Take one (hardcoded) translation file and ensure that all other translation files have the same keys in the same order

import fs from 'fs'

const main = async () => {
    const translationsDir = import.meta.dirname
    const templateFile = `${translationsDir}/en.json`
    const otherFiles = fs.readdirSync(translationsDir).map(f => {
        return `${translationsDir}/${f}`
    }).filter(f => f.endsWith('.json') && f != templateFile && !f.split('/').pop().startsWith('package'))

    const templateTranslation = JSON.parse(fs.readFileSync(templateFile).toString())

    otherFiles.forEach(file => {
        const thisTranslationOriginal = JSON.parse(fs.readFileSync(file))
        const thisTranslationNew = {}
        Object.keys(templateTranslation).forEach(k => {
            thisTranslationNew[k] = thisTranslationOriginal[k] || templateTranslation[k]
        })
        // Warn about keys present in the translation but missing from the template
        const missingFromTemplate = Object.keys(thisTranslationOriginal).filter(k => !templateTranslation.hasOwnProperty(k))
        if (missingFromTemplate.length > 0) {
            console.error(`${file}: keys missing from template will be dropped: ${missingFromTemplate.join(', ')}`)
        }
        fs.writeFileSync(file, `${JSON.stringify(thisTranslationNew, null, '    ')}\n`)
    })
}

main().catch(e => console.error(e))
