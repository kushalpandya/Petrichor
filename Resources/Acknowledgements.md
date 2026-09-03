# License & Acknowledgements

Petrichor's own source code is licensed under the MIT License. The app also relies on open source software and third-party services; this document contains the required notices for those components.

[View this document on GitHub](https://github.com/kushalpandya/Petrichor/blob/main/ACKNOWLEDGEMENTS.md)

---

## Core Dependencies

### CrescendoKit

Petrichor's playback engine and its scan-time metadata reader are provided by Crescendo, distributed as dynamically linked, embedded frameworks. Core Crescendo is proprietary software.

- [CrescendoKit](https://github.com/kushalpandya/CrescendoKit) - Proprietary (binary distribution)
- Copyright (c) Kushal Pandya

CrescendoKit ships two open source components. Neither extends to Petrichor's MIT-licensed source code, since Petrichor links both frameworks dynamically and compiles neither into its own binary.

- [FFmpeg](https://ffmpeg.org/) (via CFFmpeg) - LGPL-2.1-or-later, its own dynamically linked framework, built LGPL-only and replaceable per LGPL section 6
- [TagLib](https://taglib.org/) - MPL-1.1 (elected from dual MPL-1.1 / LGPL-2.1), used to read audio file metadata. Linked statically into `Crescendo.xcframework`, so that framework is a mixed-license artifact: the MPL's file-level copyleft covers TagLib's own unmodified sources, not the proprietary Crescendo code beside them. `COPYING.MPL` and `TagLib-NOTICE.txt` ship inside the framework.

### MIT-Licensed Dependencies

GRDB.swift and Sparkle are each licensed under the MIT License, reproduced once below:

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#### GRDB.swift

- [GRDB.swift](https://github.com/groue/GRDB.swift) - MIT
- Copyright (c) 2015-2025 Gwendal Roué

#### Sparkle

- [Sparkle](https://github.com/sparkle-project/Sparkle) - MIT
- Copyright (c) 2006-2025 Andy Matuschak, Kornel Lesiński, and contributors

---

## Integrations & Data Sources

### Integrations

- [Sluice](https://github.com/kushalpandya/Sluice) - report-triage backend powering Report a Problem (MIT)
- [Last.fm](https://www.last.fm/) - artist biography summaries
- [LRCLIB](https://lrclib.net/) - song lyrics when not available locally

### Data sources

- [MusicBrainz](https://musicbrainz.org/) - artist identifiers and Wikidata links (CC0)
- [Wikidata / Wikimedia Commons](https://www.wikidata.org/) - artist images from Wikidata entities (CC0)
- [TMDB](https://www.themoviedb.org/) - fallback source for artist images. This product uses the TMDB API but is not endorsed or certified by TMDB.

---

_Last Updated: August 2026_
