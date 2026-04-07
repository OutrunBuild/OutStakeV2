---
paths:
  - "script/**/*.sh"
  - ".githooks/*"
  - "package.json"
  - "package-lock.json"
---

- Writer: `process-implementer`
- Review: AGENTS.md §5 流程面变更流程
- Required: `bash -n <changed>.sh` | `npm ci` | `npm run quality:gate`
