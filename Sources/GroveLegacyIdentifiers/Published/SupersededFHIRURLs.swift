//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// FHIR canonical URLs this project published before the rename.
///
/// Unlike everything else in this target these are permanent. They identify extensions inside
/// `Observation`s already uploaded to research databases, and inside questionnaires authored by
/// other people, so reads must accept them forever. Nothing writes them unless a consumer opts into
/// dual-write — and not even then for the spellings in ``notReproducibleByDualWrite``.
///
/// Not deprecated: the canonical declarations that reference them are the intended, permanent use.
public enum SupersededFHIRURLs {
    // MARK: Questionnaire item extensions

    /// Validation message, in its two pre-Grove spellings — `biodesign` predates `bdh`.
    public static let validationText = [
        "http://bdh.stanford.edu/fhir/StructureDefinition/validationtext",
        "http://biodesign.stanford.edu/fhir/StructureDefinition/validationtext"
    ]

    /// iOS keyboard type hint.
    public static let iosKeyboardType = ["http://bdh.stanford.edu/fhir/StructureDefinition/ios-keyboardtype"]

    /// iOS text content type hint.
    public static let iosTextContentType = ["http://bdh.stanford.edu/fhir/StructureDefinition/ios-textcontenttype"]

    /// iOS autocapitalization hint.
    public static let iosAutocapitalizationType = [
        "http://bdh.stanford.edu/fhir/StructureDefinition/ios-autocapitalizationType"
    ]

    // MARK: Observation extensions

    /// Absolute start of an observation's effective period.
    public static let absoluteTimeRangeStart = ["https://bdh.stanford.edu/fhir/defs/absoluteTimeRangeStart"]

    /// Absolute end of an observation's effective period.
    public static let absoluteTimeRangeEnd = ["https://bdh.stanford.edu/fhir/defs/absoluteTimeRangeEnd"]

    /// Encoded `HKDevice` an observation was created from.
    public static let sourceDevice = ["https://bdh.stanford.edu/fhir/defs/sourceDevice"]

    /// Encoded `HKSourceRevision` an observation was created from.
    public static let sourceRevision = ["https://bdh.stanford.edu/fhir/defs/sourceRevision"]

    /// Encoded HealthKit sample metadata.
    ///
    /// The retired spelling nested the platform key inside the extension URL
    /// (`…/metadata/HKWeatherTemperature`), which no StructureDefinition can define.
    /// The key is now a coding in a `key` sub-extension.
    public static let metadata = ["https://bdh.stanford.edu/fhir/defs/metadata"]

    /// Identifier of the HealthKit sample a resource was created from.
    public static let healthKitSampleId = ["https://bdh.stanford.edu/fhir/defs/HealthKitSampleID"]

    // MARK: Questionnaire item controls

    /// Code system for custom questionnaire item controls.
    public static let questionnaireItemControlSystem = [
        "http://spezi.stanford.edu/fhir/CodeSystem/questionnaire-item-control"
    ]

    /// Input image of an annotate-image item control.
    ///
    /// Filed under `CodeSystem` despite being an extension, and carrying path separators that a FHIR
    /// identifier may not contain. Both are corrected in the Grove spelling.
    public static let annotateImageInputImage = [
        "http://spezi.stanford.edu/fhir/CodeSystem/questionnaire-item-control/annotate-image/input-image"
    ]

    /// Region of an annotate-image item control.
    public static let annotateImageRegion = [
        "http://spezi.stanford.edu/fhir/CodeSystem/questionnaire-item-control/annotate-image/region"
    ]

    // MARK: Reproducibility

    /// Spellings a dual-write must not reproduce, because the payload changed shape when the url did.
    ///
    /// Rewriting today's payload under one of these produces an encoding no pre-rename consumer has
    /// ever seen, so nothing is written. Metadata is the case: the key moved out of the url into a
    /// `key` sub-extension, and the entries now routed to `effective[x]` and the recording method are
    /// no longer in the envelope at all, so the pre-rename bytes cannot be rebuilt from what is there.
    /// Reads resolve these spellings like any other.
    public static let notReproducibleByDualWrite = Set(metadata)
}
