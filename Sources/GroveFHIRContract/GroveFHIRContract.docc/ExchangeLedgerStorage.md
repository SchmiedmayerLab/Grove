# The exchange ledger and its storage

<!--
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
-->

What a storage behind an ``ExchangeProducer``'s ledger must guarantee, and how common backends meet it.

## Overview

Every exchange event is immutable: a retry resends the same bytes under the same identifier, and a sequence is never handed out for other content.
``ExchangeProducer`` keeps that promise on the device.
It numbers the events of one installation, and until an exporter's receipt is released it keeps, per event key, the producer instance, the sequence, the instant and the facts (application, host, studies) the event states.
An exact redelivery after a crash, an app update or an operating-system update rebuilds byte-identical output from those frozen facts.
When anything that shapes the output but is not frozen has changed (the converter's output revision, the identity scope, the subject, the repository scope, an option, what a policy answered for the record, or record content its key does not version, such as an ECG's voltages), the event takes a new sequence instead.

Grove owns the ledger's logic and its entries.
Your application supplies only the durable storage, through ``ExchangeProducer/Storage``: a transactional map from string keys to byte values.
``ExchangeProducer/InMemoryStorage`` is the reference implementation, for tests, previews and single-process tools.

## The storage contract

A storage meets five clauses.

| Clause | Guarantee | What breaks without it |
| --- | --- | --- |
| C1 Atomicity | A transaction's writes become visible all together or not at all, including when `body` throws or the commit fails. Reads inside a transaction see its own writes. | The counter advances without the reservation, or the reverse; at worst a sequence is handed out twice. |
| C2 Durability | When `transaction` returns normally, its writes survive process termination, an operating-system crash and power loss for as long as the storage exists. On Apple platforms that takes a device-cache flush (`F_FULLFSYNC`), not only `fsync`. | A graph leaves the device under sequence *n*, then the counter's advance is undone and *n* is reused. |
| C3 Isolation | All transactions on one storage are serializable, across threads, producers and processes that open it. | Two concurrent reservations read the same counter. |
| C4 No regression, no duplication | An entry never returns to a value it held earlier, and the entries never become live in a second storage. Losing entries, some or all, is allowed. Restoring an older snapshot (a backup, a commit undone by power loss) and cloning or syncing the storage to another installation are not. | An old counter under a live producer instance, or one counter shared by two installations, reuses sequences. |
| C5 Byte-exactness | Keys compare byte for byte, and values come back byte-identical. | Entries are missed or corrupted. |

Loss is tolerated because every loss is either harmless or detected.
A lost `producer` entry mints a new producer instance; a lost reservation turns its redelivery into a new event, a duplicate and never a reuse; a lost facts entry raises ``ExchangeProducer/LedgerError/corruptEntry(key:)``.
A reservation found at or above the counter of its own instance reveals a regressed counter and raises the same error.
``ExchangeProducer/resetLedger()`` is always a safe recovery.

What Grove promises a storage in return:

- Keys are ASCII from `[A-Za-z0-9_/-]` and at most 64 bytes: `producer`, `event/<key>` and `facts/<digest>`.
- Values are UTF-8 JSON, typically under 1 KiB; accept values up to 1 MiB, as facts grow with the number of studies.
- Grove never nests transactions, never lets a transaction escape its body, and its bodies have no effect outside the transaction other than idempotent process-memory notes about which calls hold a reservation, so a storage may discard an attempt and run the body again.
- `keys(prefixedBy:)` is called only by ``ExchangeProducer/resetLedger()`` and ``ExchangeProducer/forgetReservations(madeBefore:)``.
- One storage holds one ledger and nothing else.

## Backends

| Backend | C1 | C2 | C3 | C4 | C5 |
| --- | --- | --- | --- | --- | --- |
| In memory (``ExchangeProducer/InMemoryStorage``) | Writes are buffered and applied when the body returns. | The storage lives as long as its process; exiting loses every entry, which C4 allows. | One lock per transaction. | It cannot be restored or copied. | Values are stored as given. |
| One file, rewritten atomically | Mutate a copy, write a temporary file in the same directory, rename it over the original. | `F_FULLFSYNC` on the temporary file before the rename, then `fsync` the directory. | A process lock plus `flock` on a sibling lock file that is never replaced. | Exclude the directory from backup; never sync it. | A binary property list `[String: Data]`. |
| Keychain (small or pruned ledgers) | The whole map is one item, replaced in one call. | The keychain commits the item before the call returns; that the commit survives power loss is Apple's guarantee, not verified here. | A process lock, plus a lock file for app extensions sharing the item. | A this-device-only, non-synchronizable item, guarded by a token also kept in a non-backed-up file; a missing or differing token presents an empty map. | A binary property list `[String: Data]`. |
| Core Data | A private context per transaction and one save, discarded on a throw. | Fully synchronous commits with a device-cache flush. | One process lock; an error merge policy fails a conflicting save, and the body runs again. | Exclude the store from backup; no CloudKit mirroring. | A string key with a uniqueness constraint and a binary value. |
| SQL database | One transaction per call over a relation with a unique key and a binary value. | The engine's fully durable commit, including the device-cache flush. | A transaction that takes the write lock when it begins, such as SQLite's `BEGIN IMMEDIATE`. Serializable isolation whose transactions overlap meets C3 too, with the cost described under Holds and receipts. | Exclude the database from backup; never restore it from replicas or snapshots. | A key column with binary collation and a binary value column. |

## Cost and retention

An export or retraction is one transaction that touches only the entries of its own event keys, the `producer` entry and each distinct facts entry once; a reservation that is reused writes nothing.
Releasing a receipt is at most one more transaction.
An export's receipt runs none when it reserved nothing, or when another call in the process still holds its events.
A retraction's receipt runs one whenever it reserved a retraction event, because it also forgets each deleted record's active reservation; one that reserved nothing runs none and forgets nothing.
Backends that store entries individually (in memory, Core Data, SQL) therefore cost what a call touches, whatever the ledger's size.
The single-file and keychain backends rewrite the whole map on every transaction and suit small ledgers, or ledgers you prune.

Nothing is forgotten implicitly.
A reservation stays until its receipt is released, or until you call ``ExchangeProducer/forgetReservations(madeBefore:)``, which removes the reservations made before a cutoff and the facts no remaining reservation references.
Both the cutoff and the stored instants are on the caller's clock, so choose one that tolerates clock skew.

## Holds and receipts

The entries hold no per-call state.
Live calls are tracked in process memory: when the last call in the process that holds an event finishes and any of them released it, the event's reservation is removed, and otherwise it stays for the redelivery.
A reserve notes the reservations its transaction returns from inside that transaction until it holds them, and the removing transaction checks those notes and the holds, so a release never removes a reservation another call in the process holds or is about to hold, whichever storage object, value or producer either call goes through; that call takes the release over, and the last one to finish removes the reservation.
This relies on the storage running one process's transactions one at a time, as every backend above in its primary form does with its lock or a transaction that takes the write lock when it begins.
A storage whose serializable transactions overlap, such as one that validates optimistically, still never reuses a sequence, but there a release can remove a reservation that a concurrent call has just reused, and that call's redelivery then becomes a new event, a duplicate and never a reuse.
A release only ever removes the exact reservation its call made, never a successor's or one from before a reset.
The one exception is a retraction's receipt: on release it also forgets each deleted record's active reservation, whatever event that reservation holds, because no export will release it once the record is gone.
It forgets only a reservation made under the producer instance of its own retraction events, never one from after a reset, and a reservation a live call still holds passes to that call, whose last finish removes it.
Holds do not span processes; when two live processes share one storage, a release in one can remove a reservation the other still holds, and the other's redelivery then becomes a new event, a duplicate and never a reuse.

## Topics

### The ledger

- ``ExchangeProducer``
- ``ExchangeProducer/Storage``
- ``ExchangeProducer/Transaction``
- ``ExchangeProducer/InMemoryStorage``
- ``ExchangeProducer/LedgerError``
- ``ExchangeProducer/Receipt``
