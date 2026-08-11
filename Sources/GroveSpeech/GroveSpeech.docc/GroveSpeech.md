# ``GroveSpeech``

<!--

This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

Speech recognition and synthesis for a Grove application.

## Overview

Transcribe what a participant says, and speak text back to them. The two directions are separate
modules so an app pays only for the one it uses.

`GroveSpeech` itself declares no API. It groups the family below so the package can be added as a
single dependency; import the individual products you need.

- term `GroveSpeechRecognizer`: Transcribes spoken audio to text using `SFSpeechRecognizer`.
- term `GroveSpeechSynthesizer`: Speaks text aloud using `AVSpeechSynthesizer`.

### Adding a product

Select the products you need from the Grove package and import them where you use them.
The core Grove infrastructure has to be configured first; see the `Grove` module documentation.
