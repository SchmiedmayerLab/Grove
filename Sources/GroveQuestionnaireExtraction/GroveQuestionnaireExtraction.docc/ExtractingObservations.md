# Extracting Observations from Questionnaire Responses

<!--
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#
-->

Let the instrument declare its measurements, then export the pair as an exchange record.

## Overview

Extraction is driven entirely by what the questionnaire itself states, following the SDC observation-based extraction pattern the Grove FHIR questionnaire guide adopts.
A standalone measurement is an item marked `observationExtract = true` that carries its measurement code; a panel such as blood pressure is a marked group whose children are marked as `component`:

```json
{
  "linkId": "blood-pressure",
  "type": "group",
  "code": [{"system": "http://loinc.org", "code": "85354-9"}],
  "extension": [{
    "url": "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-observationExtract",
    "valueBoolean": true
  }],
  "item": [
    {
      "linkId": "systolic",
      "type": "quantity",
      "code": [{"system": "http://loinc.org", "code": "8480-6"}],
      "extension": [{
        "url": "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-observationExtract",
        "valueCode": "component"
      }]
    }
  ]
}
```

The item's code selects the Grove measurement contract, and the contract then judges the answer: units must match the contract's UCUM unit, coded results must come from the measurement's admitted set, and a panel answered only in part refuses.
A marked item or panel the participant left unanswered states no reading and extracts nothing, even when the instrument declares it `required`: a disabled required item is legitimately absent, and enforcing required answers is the pair validator's job, not extraction's.
Nothing is inferred from answer shapes alone, so adding extraction to an instrument is a content change, not an app change.

## Exporting the pair

``QuestionnaireFHIRExporter`` exports each response with the instrument it answers as one exchange record: deterministic pseudonymous identities for the source record and every output, the Patient and carried response as content-addressed shared nodes, the study context when the producer knows the participant's enrollments, the writer's application and host device snapshots, and the conversion Provenance.
The carried response keeps the submission's business identifier as its only `identifier`, so it repeats its content key in a `grove-context-snapshot` extension.
Every extracted Observation takes the response's exact authored instant as both its effective and issued time, and states the manual-entry recording method.
The writer facts come from the writer-context extension the response carries, which an app states with `QuestionnaireResponse.apply(writerContext:)` when the response is authored; a response without one refuses.

```swift
let exporter = QuestionnaireFHIRExporter(producer: producer, repositoryScope: repositoryScope)
try await exporter.export([.init(questionnaire: questionnaire, response: response)]) { export in
    switch export.outcome {
    case .record(let record):
        staged.append(record.json)
    case .refused(let refusal):
        log(refusal)
    }
}
```

A record's version is a digest of its outputs and its conversion Provenance, which states the export's `at` instant: the same pair at the same instant restates the record byte for byte, and another instant, or another response under the same identifier, such as an amendment, is a new version of the same source record.
Stage `ExchangeRecord.json` verbatim; `ExchangeBundlePacker` packs records into the Bundle that travels and deduplicates their shared nodes.

## Withdrawing a response

When a projected response is withdrawn, it is taken back through the guide's retraction path, which suppresses every output of every version of the response's source record; the response's `entered-in-error` status is a different statement and retracts nothing.
``QuestionnaireFHIRExporter/retract(_:at:receive:)`` takes each ``QuestionnaireFHIRExporter/Withdrawal``: the pair, and when it was withdrawn.
It extracts the pair again to list the outputs it emits, so keep the pair, not the record; a pair the export refused is refused here too.
Those targets are informative: only the source record addresses the retraction, so the pair need not be the revision that was exported.

```swift
let withdrawal = QuestionnaireFHIRExporter.Withdrawal(record: record, withdrawnAt: withdrawnAt)
try await exporter.retract([withdrawal]) { retraction in
    if let record = retraction.record {
        staged.append(record.json)
    }
}
```

A retraction is keyed by its source record alone, so reporting it again repeats its key whatever its instants state, and the first one accepted wins.
Retraction records travel in a Bundle of their own: an `ExchangeBundlePacker` holds one kind.

## Consuming the record

The record is the exchange artifact: pack it, upload the Bundle, dedup on its identities, and take it back through a retraction of its source record.
A consumer can also read it back locally — `GroveHealthKitFHIR`'s sample projection turns each of the record's quantity Observations into the HealthKit sample it describes, using the minted source-output identity as the HealthKit sync identifier, so HealthKit dedup and exchange dedup ride the same identity.
An app that only wants that local readback still exports the full record and discards it afterwards; the identities it minted stay deterministic, so nothing is lost by not keeping it.

Extraction refuses loudly — ``ObservationExtractionError`` names the item and the contradiction — so an instrument is validated by exporting it, the same way the conformance gates do.
A response refused for an identity or record failure is reported the same way, and never ends the export of the others.
