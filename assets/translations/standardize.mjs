// Take one (hardcoded) translation file and ensure that all other translation files have the same keys in the same order
// Then auto-translate them using a local LibreTranslate instance (assumed to be already running on port 5000)

import fs from 'fs'
import translate from 'translate';

translate.engine = 'libre';
translate.key = process.argv[2]
translate.from = 'en'
translate.url = 'http://localhost:5000/translate'

const neverAutoTranslate = {
    steamMobile: ['*'],
    steamChat: ['*'],
    root: ['*'],
    obtainiumExportHyphenatedLowercase: ['*'],
    theme: ['de'],
    appId: ['de'],
    app: ['de'],
    placeholder: ['pl'],
    importExport: ['fr'],
    url: ['fr'],
    vivoAppStore: ['*'],
    coolApk: ['*'],
    obtainiumImport: ['nl'],
    appLogs: ['nl'],
    apks: ['vi'],
    minute: ['fr'],
    pseudoVersion: ['da'],
    tencentAppStore: ['*']
}

const translateText = (text, targetLang) => translate(text, targetLang.slice(0, 2));

const main = async () => {
    const translationsDir = import.meta.dirname
    const templateFile = `${translationsDir}/en.json`
    const otherFiles = fs.readdirSync(translationsDir).map(f => {
        return `${translationsDir}/${f}`
    }).filter(f => f.endsWith('.json') && f != templateFile && !f.split('/').pop().startsWith('package'))

    const templateTranslation = JSON.parse(fs.readFileSync(templateFile).toString())

    otherFiles.forEach(file => {
        const thisTranslationOriginal = JSON.parse(fs.readFileSync((file).toString()))
        const thisTranslationNew = {}
        Object.keys(templateTranslation).forEach(k => {
            thisTranslationNew[k] = thisTranslationOriginal[k] || templateTranslation[k]
        })
        fs.writeFileSync(file, `${JSON.stringify(thisTranslationNew, null, '    ')}\n`)
    })

    for (let i in otherFiles) {
        const file = otherFiles[i]
        const thisTranslation = JSON.parse(fs.readFileSync((file).toString()))
        const translationKeys = Object.keys(templateTranslation)
        for (let j in translationKeys) {
            const k = translationKeys[j]
            try {
                if (JSON.stringify(thisTranslation[k]) == JSON.stringify(templateTranslation[k])) {
                    const lang = file.split('/').pop().split('.')[0]
                    if (!neverAutoTranslate[k] || (neverAutoTranslate[k].indexOf('*') < 0 && neverAutoTranslate[k].indexOf(lang) < 0)) {
                        const reportLine = `${file} :::: ${k} :::: ${JSON.stringify(thisTranslation[k])}`
                        if (translate.key) {
                            try {
                                if (typeof templateTranslation[k] == 'string') {
                                    thisTranslation[k] = await translateText(thisTranslation[k], lang)
                                // } else {
                                //     const subKeys = Object.keys(templateTranslation[k])
                                //     for (let n in subKeys) {
                                //         const kk = subKeys[n]
                                //         thisTranslation[k][kk] = await translateText(thisTranslation[k][kk], lang)
                                //     }
                                }
                            } catch (e) {
                                console.log(`${reportLine} :::: ${e}`)
                            }
                        } else {
                            console.log(reportLine)
                        }
                    }
                }
            } catch (err) {
                console.error(err)
            }
        }
        fs.writeFileSync(file, `${JSON.stringify(thisTranslation, null, '    ')}\n`)
    }
}

main().catch(e => console.error)
