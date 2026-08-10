# Shared Repository

<!--
                  
This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT
             
-->

A common interface for a storage mechanism that allows multiple entities to access, provide and modify shared data.

## Overview

A Shared Repository is a software pattern that allows to easily integrate application functionality with
a data-driven control flow or applications that operate on the same data, but do not share the same processing
workflow or are split across multiple software systems.

This implementation is a modified version of the Shared Repository as described by
Buschmann et al. in _Pattern-Oriented Software Architecture: A Pattern Language for Distributed Computing_.

A ``SharedRepository`` acts as a typed collection. Stored data is defined and keyed by ``KnowledgeSource`` instances.
You can constrain the applicable ``KnowledgeSource``s by defining a ``RepositoryAnchor``

- Note: Refer to ``SendableSharedRepository`` for a `Sendable` version of a shared repository.

## Topics

### Shared Repository

- ``ValueRepository``
- ``SendableValueRepository``
- ``SharedRepository``
- ``SendableSharedRepository``

### Knowledge Sources

- ``KnowledgeSource``
- ``DefaultProvidingKnowledgeSource``
- ``ComputedKnowledgeSource``
- ``OptionalComputedKnowledgeSource``

### Implementing a Shared Repository

- ``RepositoryAnchor``
- ``RepositoryValue``
- ``AnyRepositoryValue``

### Computed Knowledge Sources

- ``SomeComputedKnowledgeSource``
- ``ComputedKnowledgeSourceStoragePolicy``
