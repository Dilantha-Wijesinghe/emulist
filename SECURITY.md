# Security Policy

## Supported versions

Only the latest release receives fixes.

## Reporting a vulnerability

Please **do not open a public issue**. Use GitHub's
[private vulnerability reporting](https://github.com/Dilantha-Wijesinghe/emulist/security/advisories/new)
instead. Include steps to reproduce (a sample file helps) and the Emulist and
macOS versions. You should hear back within a few days.

Examples of in-scope issues:

- A crafted file that crashes Emulist or worse when opened or dropped: an
  `.emulist` project, an `.emulistlook` preset, a `.cube` LUT or a movie
- Emulist modifying, replacing or deleting any file other than one you chose
  to save or export (exports never overwrite: a taken name gets " 2", " 3")
- The Fujifilm LUT download or its extraction writing outside
  `~/Library/Application Support/Emulist/Looks/Fujifilm`

## What Emulist does with your files and the network

- Footage is only ever read. Projects store references to it, never copies.
- Everything Emulist writes lives in `~/Library/Application Support/Emulist`,
  in the projects you save and in the exports you choose.
- Emulist collects no data. Its only network request is the optional
  *Download from Fujifilm* button, which fetches Fujifilm's public LUT
  package over HTTPS from fujifilm-x.com.
