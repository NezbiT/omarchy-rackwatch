#!/usr/bin/env node

const fs = require("fs")
const path = require("path")
const vm = require("vm")

const modelPath = path.join(__dirname, "..", "Model.js")
const source = fs.readFileSync(modelPath, "utf8").replace(/^\.pragma library\s*/, "")
const context = { Array, Date, JSON, Math, Number, String, isNaN }
vm.createContext(context)
vm.runInContext(source, context, { filename: modelPath })

let failures = 0

function check(label, raw, expectedOk) {
  const result = context.parseCollector(raw)
  if (result.ok !== expectedOk) {
    console.error(`FAIL: ${label} (result=${JSON.stringify(result)})`)
    failures += 1
  } else {
    console.log(`PASS: ${label}`)
  }
}

check("rejects empty output", "", false)
check("rejects JSON arrays", "[]", false)
check("requires explicit ok true", "{}", false)
check("requires snapshot data", '{"ok":true}', false)
check("rejects array snapshot data", '{"ok":true,"data":[]}', false)
check("accepts object snapshot data", '{"ok":true,"data":{}}', true)

if (failures > 0) process.exit(1)
console.log("All model tests passed.")
