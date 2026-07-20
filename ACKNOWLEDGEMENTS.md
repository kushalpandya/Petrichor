# License & Acknowledgements

Petrichor's own source code is licensed under the [MIT License](./LICENSE). The app also relies on open source software and third-party services; this document contains the required notices and license information for those components.

## At a Glance

| Component | License | Notes |
| --- | --- | --- |
| **Petrichor** | MIT | The app's own source code |
| **CrescendoKit** (Crescendo) | Proprietary | Playback engine + metadata reader (binary xcframeworks) |
| &nbsp;&nbsp;↳ FFmpeg (via CFFmpeg) | LGPL-2.1-or-later | Dynamically linked through CrescendoKit |
| &nbsp;&nbsp;↳ TagLib (via CTagLib) | MPL-1.1 | Dynamically linked through CrescendoKit |
| **SFBAudioEngine** | MIT | Legacy playback engine (SPM dependency) |
| &nbsp;&nbsp;↳ Audio codecs | BSD / LGPL / GPL | Dynamically linked through SFBAudioEngine |
| **GRDB.swift** | MIT | SQLite database layer (SPM dependency) |
| **Sparkle** | MIT | App update framework (SPM dependency) |
| **Sluice** | MIT | Backend service powering the Report a Problem feature |
| **Data sources** | CC0 / API terms | Online metadata, images, and lyrics |

The app source itself is distributed under the MIT License; every other row above is a third-party component that is not part of Petrichor's own licensed code.

---

## Core Dependencies

### CrescendoKit

Petrichor's modern playback engine and its scan-time metadata reader are provided by Crescendo, distributed via the CrescendoKit package as dynamically linked, embedded xcframeworks. Core Crescendo is proprietary software.

- **Source**: https://github.com/kushalpandya/CrescendoKit
- **License**: Proprietary (binary distribution; see the CrescendoKit LICENSE)
- **Copyright**: Copyright (c) Kushal Pandya

CrescendoKit dynamically links two open source libraries. Because both are dynamically linked and replaceable - not statically compiled into Petrichor's binary - their terms do not extend to Petrichor's MIT-licensed source code.

#### FFmpeg (via CFFmpeg)

- **Source**: https://ffmpeg.org/
- **License**: LGPL-2.1-or-later
- **Copyright**: Copyright (c) The FFmpeg developers

#### TagLib (via CTagLib)

- **Source**: https://taglib.org/
- **License**: MPL-1.1 (elected; TagLib is dual-licensed MPL-1.1 / LGPL-2.1)
- **Copyright**: Copyright (c) Scott Wheeler and contributors

Used to read audio file metadata at scan time.

### MIT-Licensed Dependencies

SFBAudioEngine, GRDB.swift, and Sparkle are each licensed under the MIT License, reproduced once below:

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

#### SFBAudioEngine

- **Source**: https://github.com/sbooth/SFBAudioEngine
- **Copyright**: Copyright (c) 2006-2025 Stephen F. Booth

##### Audio codecs

The following audio codec libraries are dynamically linked at runtime through SFBAudioEngine and are not statically compiled into Petrichor's binary. Because they are dynamically linked, their BSD/LGPL/GPL terms do not extend to Petrichor's MIT license.

- **FLAC** - BSD-3-Clause - https://xiph.org/flac/
- **Ogg Vorbis** - BSD-3-Clause - https://xiph.org/vorbis/
- **Opus** - BSD-3-Clause - https://opus-codec.org/
- **libsndfile** - LGPL-2.1 / LGPL-3.0 - https://libsndfile.github.io/libsndfile/
- **WavPack** - BSD-3-Clause - https://www.wavpack.com/
- **Monkey's Audio (MAC)** - BSD-3-Clause - https://www.monkeysaudio.com/
- **Musepack (MPC)** - BSD-3-Clause - https://www.musepack.net/
- **True Audio (TTA)** - GPL-2.0 - http://tausoft.org/
- **DSD (DSF/DFF) decoders** - mostly BSD-3-Clause - various implementations
- **libopenmpt** (MOD/S3M/XM/IT) - BSD-3-Clause - https://lib.openmpt.org/

SFBAudioEngine may utilize additional codec libraries depending on the audio format; all are dynamically linked at runtime and licensed under permissive or copyleft open source licenses.

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

_Last Updated: July 2026_
