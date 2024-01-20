// Take one (hardcoded) translation file and ensure that all other translation files have the same keys in the same order
// Then report which other translation files have identical items

const fs = require('fs')

const translationsDir = __dirname
const templateFile = `${translationsDir}/en.json`
const otherFiles = fs.readdirSync(translationsDir).map(f => {
    return `${translationsDir}/${f}`
}).filter(f => f.endsWith('.json') && f != templateFile)

const templateTranslation = require(templateFile)

otherFiles.forEach(file => {
    const thisTranslationOriginal = require(file)
    const thisTranslationNew = {}
    Object.keys(templateTranslation).forEach(k => {
        thisTranslationNew[k] = thisTranslationOriginal[k] || templateTranslation[k]
    })
    fs.writeFileSync(file, `${JSON.stringify(thisTranslationNew, null, '    ')}\n`)
});

otherFiles.forEach(file => {
    const thisTranslation = require(file)
    Object.keys(templateTranslation).forEach(k => {
        if (JSON.stringify(thisTranslation[k]) == JSON.stringify(templateTranslation[k])) {
            console.log(`${file} :::: ${k} :::: ${JSON.stringify(thisTranslation[k])}`)
        }
    })
});