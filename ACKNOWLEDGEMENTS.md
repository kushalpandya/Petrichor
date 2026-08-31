# License & Acknowledgements

Petrichor's own source code is licensed under the [MIT License](./LICENSE). The app also relies on open source software and third-party services; this document contains the required notices and license information for those components.

## At a Glance

| Component | License | Notes |
| --- | --- | --- |
| **Petrichor** | MIT | The app's own source code |
| **CrescendoKit** (Crescendo) | Proprietary | Playback engine + metadata reader (binary xcframeworks) |
| &nbsp;&nbsp;↳ FFmpeg (via CFFmpeg) | LGPL-2.1-or-later | Dynamically linked through CrescendoKit |
| &nbsp;&nbsp;↳ TagLib | MPL-1.1 | Statically embedded in `Crescendo.xcframework` |
| **GRDB.swift** | MIT | SQLite database layer (SPM dependency) |
| **Sparkle** | MIT | App update framework (SPM dependency) |
| **Sluice** | MIT | Backend service powering the Report a Problem feature |
| **Data sources** | CC0 / API terms | Online metadata, images, and lyrics |

The app source itself is distributed under the MIT License; every other row above is a third-party component that is not part of Petrichor's own licensed code.

---

## Core Dependencies

### CrescendoKit

Petrichor's playback engine and its scan-time metadata reader are provided by Crescendo, distributed via the CrescendoKit package as dynamically linked, embedded xcframeworks. Core Crescendo is proprietary software.

- **Source**: https://github.com/kushalpandya/CrescendoKit
- **License**: Proprietary (binary distribution; see the CrescendoKit LICENSE)
- **Copyright**: Copyright (c) Kushal Pandya

CrescendoKit ships two open source components, on different terms. Neither extends to Petrichor's MIT-licensed source code: Petrichor links both xcframeworks dynamically and compiles neither into its own binary.

#### FFmpeg (via CFFmpeg)

- **Source**: https://ffmpeg.org/
- **License**: LGPL-2.1-or-later
- **Copyright**: Copyright (c) The FFmpeg developers

Shipped as its own xcframework, built LGPL-only (no GPL or non-free components) and dynamically linked, so it stays replaceable per LGPL section 6.

#### TagLib

- **Source**: https://taglib.org/
- **License**: MPL-1.1 (elected; TagLib is dual-licensed MPL-1.1 / LGPL-2.1)
- **Copyright**: Copyright (c) Scott Wheeler and contributors

Used to read audio file metadata at scan time. TagLib is linked **statically** into `Crescendo.xcframework`, making that a mixed-license artifact: the MPL's file-level copyleft covers TagLib's own sources, which are used unmodified and excluded from the Crescendo EULA, and not the proprietary Crescendo code in the same binary. `COPYING.MPL` and `TagLib-NOTICE.txt` are carried inside the framework's `Resources/`, and each CrescendoKit release attaches the verified TagLib source archive as the corresponding source.

### MIT-Licensed Dependencies

GRDB.swift and Sparkle are each licensed under the MIT License, reproduced once below:

```
MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

#### GRDB.swift

- **Source**: https://github.com/groue/GRDB.swift
- **Copyright**: Copyright (c) 2015-2025 Gwendal Roué

#### Sparkle

- **Source**: https://github.com/sparkle-project/Sparkle
- **Copyright**: Copyright (c) 2006-2025 Andy Matuschak, Kornel Lesiński, and contributors

---

## Integrations & Data Sources

### Integrations

- **Sluice** - https://github.com/kushalpandya/Sluice
  - Report-triage backend that powers Petrichor's Report a Problem feature.
  - License: MIT
- **Last.fm** - https://www.last.fm/
  - Used to fetch artist biography summaries.
- **LRCLIB** - https://lrclib.net/
  - Used to fetch song lyrics when not available locally.

### Data sources

- **MusicBrainz** - https://musicbrainz.org/
  - Used to search for artist identifiers and Wikidata links.
  - Licensed under [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
- **Wikidata / Wikimedia Commons** - https://www.wikidata.org/
  - Used to resolve artist images from Wikidata entities.
  - Licensed under [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
- **TMDB (The Movie Database)** - https://www.themoviedb.org/
  - Used as a fallback source for artist images.
  - This product uses the TMDB API but is not endorsed or certified by TMDB.

---

_Last Updated: August 2026_
