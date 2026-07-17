# License & Acknowledgements

Petrichor's own source code is licensed under the MIT License. The app also relies on open source software and third-party services; this document contains the required notices for those components.

[View this document on GitHub](https://github.com/kushalpandya/Petrichor/blob/main/ACKNOWLEDGEMENTS.md)

---

## Core Dependencies

### CrescendoKit

Petrichor's modern playback engine and its scan-time metadata reader are provided by Crescendo, distributed as dynamically linked, embedded frameworks. Core Crescendo is proprietary software.

- [CrescendoKit](https://github.com/kushalpandya/CrescendoKit) - Proprietary (binary distribution)
- Copyright (c) Kushal Pandya

CrescendoKit dynamically links two open source libraries. Because both are dynamically linked and replaceable, their terms do not extend to Petrichor's MIT-licensed source code.

- [FFmpeg](https://ffmpeg.org/) (via CFFmpeg) - LGPL-2.1-or-later
- [TagLib](https://taglib.org/) (via CTagLib) - MPL-1.1, used to read audio file metadata

### MIT-Licensed Dependencies

SFBAudioEngine, GRDB.swift, and Sparkle are each licensed under the MIT License, reproduced once below:

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#### SFBAudioEngine

- [SFBAudioEngine](https://github.com/sbooth/SFBAudioEngine) - MIT
- Copyright (c) 2006-2025 Stephen F. Booth

The following audio codec libraries are dynamically linked at runtime through SFBAudioEngine and are not statically compiled into Petrichor. Because they are dynamically linked, their terms do not extend to Petrichor's MIT license.

- [FLAC](https://xiph.org/flac/) - BSD-3-Clause
- [Ogg Vorbis](https://xiph.org/vorbis/) - BSD-3-Clause
- [Opus](https://opus-codec.org/) - BSD-3-Clause
- [libsndfile](https://libsndfile.github.io/libsndfile/) - LGPL-2.1 / LGPL-3.0
- [WavPack](https://www.wavpack.com/) - BSD-3-Clause
- [Monkey's Audio](https://www.monkeysaudio.com/) - BSD-3-Clause
- [Musepack](https://www.musepack.net/) - BSD-3-Clause
- [True Audio](http://tausoft.org/) - GPL-2.0
- [libopenmpt](https://lib.openmpt.org/) - BSD-3-Clause (MOD/S3M/XM/IT)

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
