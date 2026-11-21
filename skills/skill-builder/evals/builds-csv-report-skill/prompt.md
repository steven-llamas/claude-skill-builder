---
tags: [skill-builder]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

i need a skill that takes our weekly sales export (csv, columns: date, region, sku, units, unit_price) and writes a short markdown summary: total revenue, top 3 skus by revenue, and any rows with negative units flagged. call it summarizing-sales-csvs and put it in ./out. dont ask me anything, pick sensible defaults and tell me what you assumed
