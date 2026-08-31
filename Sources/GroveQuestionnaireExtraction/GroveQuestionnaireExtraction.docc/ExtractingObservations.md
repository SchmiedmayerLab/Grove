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

Let the instrument declare its measurements, then project the pair into an exchange bundle.

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

The item's code selects the Grove measurement contract, and the contract then judges the answer: units must match the contract's UCUM unit, coded results must come from the measurement's admitted set, and a panel missing a component refuses.
Nothing is inferred from answer shapes alone, so adding extraction to an instrument is a content change, not an app change.

## Projecting the pair

``QuestionnaireExchangeProjection/exchangeGraph(questionnaire:response:context:)`` mints the full exchange bundle: deterministic pseudonymous identities for the source record and every output, the Patient and carried response as resolvable entries, the writer's application and host device snapshots, and the transform Provenance.
Every extracted Observation takes the response's exact authored instant as both its effective and issued time, and states the manual-entry recording method.
A received response supplies its writer facts through the writer-context extension it carries; a local projection states them via ``QuestionnaireExtractionContext/localWriter``:

```swift
let graph = try QuestionnaireExchangeProjection.exchangeGraph(
    questionnaire: questionnaire,
    response: response,
    context: QuestionnaireExtractionContext(
        patient: patient,
        eventIdentifier: eventIdentifier,
        identityScope: identityScope,
        repositoryScope: repositoryScope,
        entryNodeIdentifierSystem: nodeSystem,
        conversionInstant: persistedConversionInstant
    )
)
```

## Consuming the bundle

The graph is the exchange artifact: upload it, dedup on its identities, retract by them.
A consumer can also read it back locally — `GroveHealthKitFHIR`'s sample projection turns each of the bundle's quantity Observations into the HealthKit sample it describes, using the minted source-output identity as the HealthKit sync identifier, so HealthKit dedup and exchange dedup ride the same identity.
An app that only wants that local readback still projects the full graph and simply discards the bundle afterwards; the identities it minted stay deterministic, so nothing is lost by not keeping it.

Extraction refuses loudly — ``ObservationExtractionError`` names the item and the contradiction — so an instrument is validated by projecting it, the same way the conformance gates do.
