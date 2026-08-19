# ``GeneratedOpenAIClient``

<!--

This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

The generated OpenAI API client, with the retry and authentication policy around it.

## Overview

The bulk of this target is generated from the OpenAI OpenAPI specification by
`swift-openapi-generator` and is not documented here — consult the specification instead.

What is hand-written is the policy wrapped around the transport: how a request authenticates, and
what happens when the service answers with a retryable signal.

## Topics

### Authentication

- ``RemoteLLMInferenceAuthToken``

### Retrying

- ``RetryPolicy``
- ``RetryableSignal``
- ``DelayPolicy``
