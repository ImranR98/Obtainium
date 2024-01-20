// Take one (hardcoded) translation file and ensure that all other translation files have the same keys in the same order

const fs = require('fs')

const translationsDir = __dirname
const templateFile = `${translationsDir}/en.json`
const otherFiles = fs.readdirSync(translationsDir).map(f => {
    return `${translationsDir}/${f}`}).filter(f => f.endsWith('.json') && f != templateFile)

const templateTranslation = require(templateFile)

otherFiles.forEach(file => {
    console.log(file)
    const thisTranslationOriginal = require(file)
    const thisTranslationNew = {}
    Object.keys(templateTranslation).forEach(k => {
        thisTranslationNew[k] = thisTranslationOriginal[k] || templateTranslation[k]
    })
    fs.writeFileSync(file, `${JSON.stringify(thisTranslationNew, null, '    ')}\n`)
});