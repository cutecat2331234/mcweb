import hljs from 'highlight.js/lib/core'
import bash from 'highlight.js/lib/languages/bash'
import css from 'highlight.js/lib/languages/css'
import go from 'highlight.js/lib/languages/go'
import java from 'highlight.js/lib/languages/java'
import javascript from 'highlight.js/lib/languages/javascript'
import json from 'highlight.js/lib/languages/json'
import php from 'highlight.js/lib/languages/php'
import python from 'highlight.js/lib/languages/python'
import ruby from 'highlight.js/lib/languages/ruby'
import rust from 'highlight.js/lib/languages/rust'
import sql from 'highlight.js/lib/languages/sql'
import typescript from 'highlight.js/lib/languages/typescript'
import xml from 'highlight.js/lib/languages/xml'
import yaml from 'highlight.js/lib/languages/yaml'
import 'highlight.js/styles/github.css'

const languages: Array<[string, typeof javascript]> = [
  ['bash', bash],
  ['sh', bash],
  ['shell', bash],
  ['css', css],
  ['go', go],
  ['java', java],
  ['javascript', javascript],
  ['js', javascript],
  ['json', json],
  ['php', php],
  ['python', python],
  ['py', python],
  ['ruby', ruby],
  ['rb', ruby],
  ['rust', rust],
  ['rs', rust],
  ['sql', sql],
  ['typescript', typescript],
  ['ts', typescript],
  ['html', xml],
  ['xml', xml],
  ['yaml', yaml],
  ['yml', yaml],
]

languages.forEach(([name, lang]) => hljs.registerLanguage(name, lang))

export function highlightCodeBlocks(root: ParentNode = document) {
  root.querySelectorAll('pre code[data-lang], code[data-lang]').forEach((element) => {
    const el = element as HTMLElement
    if (el.dataset.highlighted === 'yes') return

    const lang = el.dataset.lang?.toLowerCase()
    if (lang && hljs.getLanguage(lang)) {
      hljs.highlightElement(el)
    } else if (lang) {
      hljs.highlightElement(el, { language: 'plaintext' })
    }
    el.dataset.highlighted = 'yes'
  })
}
