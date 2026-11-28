//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// Converts typed provider records into exchange records.
///
/// Each conversion either produces a complete record or states why it omits a source element. The converter performs no
/// fetching, resampling or retrieval-time substitution: the caller acquires the records and persists the
/// ``ProviderConversionContext`` before converting.
public enum ProviderFHIRConverter {
    /// Converts one Withings measure group, one result per distinct source token.
    ///
    /// A blood pressure pair is atomic within its group; a heart rate in the same group is a record of its own.
    public static func convert(_ group: WithingsMeasureGroup, context: ProviderConversionContext) throws -> [ProviderConversionResult] {
        try WithingsConversion.convert(group, context: context)
    }

    /// Converts one Withings summary, one result per populated field, each under the field's own source token.
    public static func convert(_ summary: WithingsSummary, context: ProviderConversionContext) throws -> [ProviderConversionResult] {
        try WithingsConversion.convert(summary, context: context)
    }

    /// Converts one Oura document.
    public static func convert(_ record: OuraRecord, context: ProviderConversionContext) throws -> ProviderConversionResult {
        try OuraConversion.convert(record, context: context)
    }

    /// Converts one Google Health data point; the admitted fields of one data point share one record.
    public static func convert(_ dataPoint: GoogleHealthDataPoint, context: ProviderConversionContext) throws -> ProviderConversionResult {
        try GoogleHealthConversion.convert(dataPoint, context: context)
    }

    /// Converts one native provider recording into a recording document that references its file.
    ///
    /// The document states the file's checksum and byte count and invents neither a sampling period nor a scalar result.
    public static func convert(_ recording: ProviderNativeRecording, context: ProviderConversionContext) throws -> ProviderConversionResult {
        try ProviderRecordingConversion.convert(recording, context: context)
    }
}
