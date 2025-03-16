// Take one (hardcoded) translation file and ensure that all other translation files have the same keys in the same order
// Then report which other translation files have identical items (or auto-translate them if a DeepL API key is provided)

const fs = require('fs')
const https = require('https')

const deeplAPIKey = process.argv[2]

const neverAutoTranslate = {
    steamMobile: ['*'],
    steamChat: ['*'],
    root: ['*'],
    obtainiumExportHyphenatedLowercase: ['*'],
    theme: ['de'],
    appId: ['de'],
    placeholder: ['pl'],
    importExport: ['fr'],
    url: ['fr'],
    tencentAppStore: ['*']
}

const translateText = async (text, targetLang, authKey) => {
    return new Promise((resolve, reject) => {
        const postData = `text=${encodeURIComponent(text)}&target_lang=${encodeURIComponent(targetLang)}&source_lang=EN`
        const options = {
            hostname: 'api-free.deepl.com',
            port: 443,
            path: '/v2/translate',
            method: 'POST',
            headers: {
                'Authorization': `DeepL-Auth-Key ${authKey}`,
                'Content-Type': 'application/x-www-form-urlencoded',
                'Content-Length': Buffer.byteLength(postData)
            }
        }
        const req = https.request(options, (res) => {
            let responseData = ''
            res.on('data', (chunk) => {
                responseData += chunk
            })
            res.on('end', () => {
                try {
                    const jsonResponse = JSON.parse(responseData)
                    resolve(jsonResponse)
                } catch (error) {
                    reject(error)
                }
            })
        })
        req.on('error', (error) => {
            reject(error)
        })
        req.write(postData)
        req.end()
    })
}

const main = async () => {
    const translationsDir = __dirname
    const templateFile = `${translationsDir}/en.json`
    const otherFiles = fs.readdirSync(translationsDir).map(f => {
        return `${translationsDir}/${f}`
    }).filter(f => f.endsWith('.json') && f != templateFile)

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
                        if (deeplAPIKey) {
                            const translateFunc = async (str) => {
                                await new Promise((resolve, reject) => {
                                    setTimeout(() => {
                                        resolve()
                                    }, Math.random() * 10000); // Try to avoid rate limit
                                })
                                const response = await translateText(str, lang, deeplAPIKey)
                                if (response.translations) {
                                    return response.translations[0].text
                                } else {
                                    throw JSON.stringify(response)
                                }
                            }
                            try {
                                if (typeof templateTranslation[k] == 'string') {
                                    thisTranslation[k] = await translateFunc(thisTranslation[k])
                                } else {
                                    const subKeys = Object.keys(templateTranslation[k])
                                    for (let n in subKeys) {
                                        const kk = subKeys[n]
                                        thisTranslation[k][kk] = await translateFunc(thisTranslation[k][kk])
                                    }
                                }
                            } catch (e) {
                                if (typeof e == 'string') {
                                    console.log(`${reportLine} :::: ${e}`)
                                } else {
                                    throw e
                                }
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
