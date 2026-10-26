---
slug: open-any-folder-in-longbook
title: Open any folder in longbook
seo_title: Open a longbook from any folder
description: longbook keeps everything in one open, documented file. Open it from iCloud, this device or any folder, and let any tool or AI write it.
card: Your longbook is one open file in a folder you choose. Open another folder, or have any tool write one longbook opens.
lead: Worried your money records are locked inside one app? longbook keeps everything in one open, documented file, in a folder you choose. This is how to open another folder in longbook, what the file looks like, and how any tool or AI can write one that longbook opens.
date: 2026-10-26
image: /blog/media/open-any-folder/share.jpg
image_alt: Open any folder in longbook, on the longbook blog
---

## One file, in a folder you choose

Afraid of losing your records the day an app closes? Your longbook is a folder of plain files, and everything in it lives in one file: `financial_memory.json`. It holds your commitments, every charge past and planned, your accounts, your people and your tags. Beside it sit `longbook.schema.json`, which describes the format, `llms.txt`, the guide an AI reads before it writes, and a `documents` folder for your statements.

The folder can be in your iCloud Drive, where it syncs to your other devices, on this device only, or in any folder you can open from Files on iPhone or Finder on Mac. longbook reads and writes the folder you choose, and nothing else.

## Open another folder

Keeping a second longbook, or one a tool made for you? Open it from Settings.

1. Open **Settings**, then **Data & privacy**.
2. Choose **Open Another Folder…**.
3. Pick the folder that holds the `financial_memory.json`, not the file itself.

longbook checks the file first. If it reads, longbook switches to that folder and opens it. Your current folder stays exactly as it is: nothing in it is written, moved or deleted, and you can open it again the same way.

## What the format is

Wondering what a tool has to write for longbook to read it? The format is open and documented in two places:

- [The schema](https://longbook.app/schema/longbook.schema.json) names every field, which ones are required, and what each one means.
- [The guide for AI](https://longbook.app/llms.txt) explains how to write the file well: one row per charge, amounts never converted between currencies, and nothing secret such as a card number.

Three fields are required at the top: `app`, which is always `longbook`, `version`, which is `3`, and `commitments`. Each commitment needs an `id`, a `name`, an `amount`, a `currency`, a `billing_cycle` and a `status`. Charges are optional, and each one names its commitment, its date, its amount and whether it was paid.

This is a complete longbook with one subscription and its next payment planned:

```json
{
  "app": "longbook",
  "version": 3,
  "commitments": [
    {
      "id": "9f6c1b52-3d1e-4a8b-9c47-2f0e6a1d5b83",
      "name": "Netflix",
      "amount": 649,
      "currency": "INR",
      "billing_cycle": "monthly",
      "status": "active"
    }
  ],
  "charges": [
    {
      "commitment_id": "9f6c1b52-3d1e-4a8b-9c47-2f0e6a1d5b83",
      "date": "2026-11-05",
      "amount": 649,
      "paid": false,
      "basis": "plan"
    }
  ]
}
```

Save it as `financial_memory.json` in an empty folder, open that folder in longbook, and Netflix shows up with its payment on 5 November.

## Any tool or AI can write it

Want a spreadsheet, a script or your own AI to keep your longbook? Point it at the schema and the guide, ask it to write `financial_memory.json` in that format, and open the folder in longbook. A file made that way opens like one longbook made itself.

When an AI is connected to longbook through its own connector, it reads the guide before every write, and the changes it suggests wait in Proposals for you to keep or undo. [Every change your AI makes](/features/review-every-change-your-ai-makes/) is reviewed before you keep it.

## When a file doesn't match

Concerned that a wrong file could break your longbook? It can't. When the folder you pick has no `financial_memory.json`, or the file isn't in longbook's format, longbook says so and keeps the folder you were using. Nothing is written to either folder.

The usual reasons a file doesn't read are a missing required field, a `version` other than `3`, a `billing_cycle` that isn't `monthly`, `yearly`, `custom` or `once`, or a file that isn't JSON at all. Check the file against [the schema](https://longbook.app/schema/longbook.schema.json), fix what it names, and open the folder again.

If something here is wrong, or you want a step explained further, write to [contact@longbook.app](mailto:contact@longbook.app).
