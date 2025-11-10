# License & Acknowledgements

Petrichor uses various open source software components. This document contains the required notices and license information for these components.

---

## Core Dependencies

### SFBAudioEngine

- **Source**: https://github.com/sbooth/SFBAudioEngine
- **License**: MIT License
- **Copyright**: Copyright (c) 2006-2025 Stephen F. Booth

```
MIT License

Copyright (c) 2006-2025 Stephen F. Booth

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

### GRDB.swift

- **Source**: https://github.com/groue/GRDB.swift
- **License**: MIT License
- **Copyright**: Copyright (c) 2015-2025 Gwendal Roué

### Sparkle

- **Source**: https://github.com/sparkle-project/Sparkle
- **License**: MIT License
- **Copyright**: Copyright (c) 2006-2025 Andy Matuschak, Kornel Lesiński, and contributors

---

## Audio Codec Libraries

The following audio codec libraries are dynamically linked through SFBAudioEngine and are not distributed with Petrichor's source code. These libraries are used at runtime for decoding various audio formats.

### FLAC (Free Lossless Audio Codec)

- **Source**: https://xiph.org/flac/
- **License**: BSD-3-Clause License
- **Copyright**: Copyright (c) 2000-2009 Josh Coalson, Copyright (c) 2011-2023 Xiph.Org Foundation

The FLAC library is licensed under the BSD 3-Clause License, which is permissive and compatible with Petrichor's MIT license.

### Ogg Vorbis

- **Source**: https://xiph.org/vorbis/
- **License**: BSD-3-Clause License
- **Copyright**: Copyright (c) 2002-2020 Xiph.org Foundation

### Opus

- **Source**: https://opus-codec.org/
- **License**: BSD-3-Clause License
- **Copyright**: Copyright (c) 2001-2011 Xiph.Org Foundation and contributors

### libsndfile

- **Source**: https://libsndfile.github.io/libsndfile/
- **License**: LGPL-2.1 or LGPL-3.0
- **Copyright**: Copyright (c) 1999-2023 Erik de Castro Lopo and others

This library is used for reading and writing various audio file formats. As it is dynamically linked and licensed under LGPL, Petrichor's MIT license remains unaffected.

### WavPack

- **Source**: https://www.wavpack.com/
- **License**: BSD-3-Clause License
- **Copyright**: Copyright (c) 1998-2023 David Bryant

### Monkey's Audio (MAC)

- **Source**: https://www.monkeysaudio.com/
- **License**: BSD-3-Clause License
- **Copyright**: Copyright (c) 2000-2023 Matthew T. Ashland

### Musepack (MPC)

- **Source**: https://www.musepack.net/
- **License**: BSD-3-Clause License
- **Copyright**: Copyright (c) 2005-2023 The Musepack Development Team

### True Audio (TTA)

- **Source**: http://tausoft.org/
- **License**: GPL-2.0
- **Copyright**: Copyright (c) 1999-2023 Alexander Djourik

**Note**: True Audio codec is licensed under GPL-2.0. Since it is dynamically linked and not statically compiled into Petrichor, the GPL does not extend to Petrichor's codebase.

### DSD (Direct Stream Digital) Decoders

- **Various implementations**: DSF, DFF format support
- **License**: Varies by implementation (mostly BSD-3-Clause)

### MOD/S3M/XM/IT Tracker Formats

- **libopenmpt**: https://lib.openmpt.org/
- **License**: BSD-3-Clause License
- **Copyright**: Copyright (c) 2004-2023 OpenMPT Project Developers and Contributors

### Additional Codec Libraries

SFBAudioEngine may utilize additional codec libraries depending on the audio format. All libraries are:

- Dynamically linked at runtime
- Not distributed with Petrichor's source code
- Licensed under permissive open source licenses (BSD, LGPL, or GPL)

---

## Dynamic Linking Notice

All audio codec libraries listed above are **dynamically linked** at runtime and are **not statically compiled** into Petrichor's binary. This means:

1. The GPL/LGPL-licensed codecs do not affect Petrichor's MIT license
2. Users can replace or update codec libraries independently
3. Petrichor's source code remains under MIT license
4. Codec libraries are loaded from the system or SFBAudioEngine framework at runtime

---

## License Summary

| Component      | License      | Distributed With Source |
| -------------- | ------------ | ----------------------- |
| Petrichor      | MIT          | Yes                     |
| SFBAudioEngine | MIT          | No (SPM dependency)     |
| GRDB.swift     | MIT          | No (SPM dependency)     |
| Sparkle        | MIT          | No (SPM dependency)     |
| Audio Codecs   | BSD/LGPL/GPL | No (dynamic linking)    |

---

## Full License Texts

For the complete license texts of all components, please refer to:

- Petrichor: [LICENSE](../LICENSE) file in the root directory
- SFBAudioEngine: https://github.com/sbooth/SFBAudioEngine/blob/master/LICENSE.txt
- GRDB.swift: https://github.com/groue/GRDB.swift/blob/master/LICENSE
- Sparkle: https://github.com/sparkle-project/Sparkle/blob/2.x/LICENSE

Individual codec library licenses can be found in their respective source repositories.

---

## Acknowledgments

Petrichor is grateful to all the open source projects and their contributors that make high-quality audio playback on macOS possible.

_Last Updated: November 2025_
