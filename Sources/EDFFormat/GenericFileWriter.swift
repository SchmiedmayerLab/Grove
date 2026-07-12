//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import ByteCoding
import Foundation
import NIO
import NIOFoundationCompat


/// A EDF file writer.
///
/// A file writer for a ``EDFSample``.
///
/// Below is a short code example on how to use the file writer class.
///
/// ```swift
/// let url = URL(filePath: "/your/file/path.edf") // make sure the file exists
///
/// let file: FileInformation = // ...
/// let signals: [Signal] = [
///     // define your signal descriptions ...
/// ]
///
/// let writer = try EDFFileWriter(url: url, information: file, signals: signals)
///
/// // make sure to write the file header once ...
/// try writer.writeHeader()
///
/// // continuously add your data records ...
/// let record = DataRecord(channels: [
///     // add your `Channel` data with `EDFSample`s
/// ])
/// try writer.addRecord(record)
///
/// // ...
///
/// // close file once finished
/// try writer.close()
/// ```
@available(iOS 18, macOS 15, watchOS 11, *)
public typealias EDFFileWriter = GenericFileWriter<EDFSample>


/// A BDF file writer.
///
/// A file writer for a ``BDFSample``.
///
/// Below is a short code example on how to use the file writer class.
///
/// ```swift
/// let url = URL(filePath: "/your/file/path.bdf") // make sure the file exists
///
/// let file: FileInformation = // ...
/// let signals: [Signal] = [
///     // define your signal descriptions ...
/// ]
///
/// let writer = try BDFFileWriter(url: url, information: file, signals: signals)
///
/// // make sure to write the file header once ...
/// try writer.writeHeader()
///
/// // continuously add your data records ...
/// let record = DataRecord(channels: [
///     // add your `Channel` data with `EDFSample`s
/// ])
/// try writer.addRecord(record)
///
/// // ...
///
/// // close file once finished
/// try writer.close()
/// ```
@available(iOS 18, macOS 15, watchOS 11, *)
public typealias BDFFileWriter = GenericFileWriter<BDFSample>


/// A EDF/BDF file writer for a given `Sample` type.
///
/// A file writer for a generic ``Sample`` type.
///
/// - Tip: Use the ``EDFFileWriter`` or ``BDFFileWriter`` typealias for the respective sample types
///     to generate EDF/EDF+ or BDF/BDF+ files.
///
/// Below is a short code example on how to use the file writer class.
///
/// ```swift
/// let url = URL(filePath: "/your/file/path.edf") // make sure the file exists
///
/// let file: FileInformation = // ...
/// let signals: [Signal] = [
///     // define your signal descriptions ...
/// ]
///
/// let writer = try GenericFileWriter<EDFSample>(url: url, information: file, signals: signals)
///
/// // make sure to write the file header once ...
/// try writer.writeHeader()
///
/// // continuously add your data records ...
/// let record = DataRecord(channels: [
///     // add your `Channel` data
/// ])
/// try writer.addRecord(record)
///
/// // ...
///
/// // close file once finished
/// try writer.close()
/// ```
@available(iOS 18, macOS 15, watchOS 11, *)
public final class GenericFileWriter<S: Sample> {
    private static var dataRecordsCountOffset: UInt64 {
        8 + 80 + 80 + 8 + 8 + 8 + 44
    }

    /// The file format.
    public let format: FileFormat
    /// File information
    public var fileInformation: FileInformation
    /// The format of the file records (e.g., `EDF+C`).
    private let dataFormat: String
    /// Array of signal descriptions.
    public let signals: [Signal]

    private let fileHandle: FileHandle
    private let lock = NSLock()
    private var dataRecordsCount: Int = -1
    private var writerIndex: UInt64 = 0
    private var didClose = false


    /// The channel count this file contains.
    public var channelCount: Int {
        signals.count
    }

    /// Retrieve the data record format (e.g., continuous vs. interrupted recording).
    ///
    /// Storing information about continuous vs. interrupted recording is only supported in
    /// EDF+ or BDF+ files. Plain EDF or BDF files have this field as reserved and a file
    /// might contain arbitrary string output if not adhering to the specification.
    public var recordingFormat: RecordingFormat {
        RecordingFormat(from: dataFormat)
    }

    private var headerLength: Int {
        256 * (1 + channelCount)
    }

    private init(url: URL, format: FileFormat, fileInformation: FileInformation, dataFormat: String?, signals: [Signal]) throws {
        self.format = format
        self.fileInformation = fileInformation
        self.dataFormat = dataFormat ?? ""
        self.signals = signals

        self.fileHandle = try FileHandle(forWritingTo: url)

        try verifyAsciiInput(channelCount, maxLength: 4, for: "channelCount")
        try verifyAsciiInput(headerLength, maxLength: 8, for: "headerLength")

        try fileInformation.verifyAsciiInputs()
        for signal in signals {
            try signal.verifyAsciiInputs()
        }
    }

    /// Update the file information of the file.
    ///
    /// This updates the ``FileInformation`` of a file to modify it after instantiation (e.g., update the record duration or recording start date).
    ///
    /// - Important: If you already called ``writeHeader()`` make sure to re-write the header after a call to this method to ensure
    ///     that the updated information is persisted on disk as well.
    ///
    /// - Parameter fileInformation: The updated ``FileInformation``.
    public func updateFileInformation(_ fileInformation: FileInformation) {
        lock.lock()
        defer {
            lock.unlock()
        }

        self.fileInformation = fileInformation
    }


    /// Write the file header to disk.
    /// - Throws: Throws if file access fails.
    public func writeHeader() throws {
        lock.lock()
        defer {
            lock.unlock()
        }

        self.writerIndex = 0
        try fileHandle.seek(toOffset: writerIndex) // make sure we are at the start

        var header = ByteBuffer()
        header.reserveCapacity(headerLength)
        self.encodeHeader(to: &header)


        let headerData = header.getData(at: 0, length: header.readableBytes) ?? .init()
        try fileHandle.write(contentsOf: headerData)

        writerIndex += UInt64(headerData.count)
    }

    /// Append new data record to the file.
    /// - Parameter record: The set of sample data grouped by their channel.
    /// - Throws: Throws if file access fails or invalid data record was provided (e.g., invalid channel count or sample count).
    public func addRecord(_ record: DataRecord<S>) throws {
        lock.lock()
        defer {
            lock.unlock()
        }

        if writerIndex == 0 {
            throw EDFEncodingError.headerNotWritten
        }

        try fileHandle.seek(toOffset: writerIndex)

        if record.channels.count != channelCount { // == signals.count
            throw EDFEncodingError.invalidChannelCount(expected: channelCount, received: record.channels.count)
        }

        var totalSampleCount = 0 // count to reserve capacity later on
        for index in signals.indices {
            let signal = signals[index]
            let channel = record.channels[index]

            if channel.samples.count != signal.sampleCount {
                throw EDFEncodingError.invalidSampleCount(channel: signal.label, expected: signal.sampleCount, received: channel.samples.count)
            }
            totalSampleCount += signal.sampleCount
        }

        var recordBuffer = ByteBuffer()
        switch format {
        case .edf:
            recordBuffer.reserveCapacity(16 * totalSampleCount)
        case .bdf:
            recordBuffer.reserveCapacity(24 * totalSampleCount)
        }
        record.encode(to: &recordBuffer)

        let recordData = recordBuffer.getData(at: 0, length: recordBuffer.readableBytes) ?? .init()
        try fileHandle.write(contentsOf: recordData)

        writerIndex += UInt64(recordData.count)

        if self.dataRecordsCount < 0 {
            self.dataRecordsCount = 0
        }
        self.dataRecordsCount += 1
        
        try verifyAsciiInput(dataRecordsCount, maxLength: 8, for: "dataRecordsCount")

        try updateRecordsCount()
    }

    private func updateRecordsCount() throws {
        // update the dataRecordsCount
        try fileHandle.seek(toOffset: Self.dataRecordsCountOffset)

        var countBuffer = ByteBuffer()
        countBuffer.reserveCapacity(8)
        countBuffer.writeEDFAscii(dataRecordsCount, length: 8)

        let countData = countBuffer.getData(at: 0, length: countBuffer.readableBytes) ?? .init()
        try fileHandle.write(contentsOf: countData)
    }

    /// Finish writing file by closing the file handle.
    /// - Throws: Throws if file interaction fails.
    public func close() throws {
        lock.lock()
        defer {
            lock.unlock()
        }

        if didClose {
            return
        }

        if dataRecordsCount < 0 {
            // no records got written. so set to zero
            dataRecordsCount = 0
            try updateRecordsCount()
        }

        try fileHandle.close()
        didClose = true
    }

    deinit {
        try? close()
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension GenericFileWriter: @unchecked Sendable {}


@available(iOS 18, macOS 15, watchOS 11, *)
extension GenericFileWriter {
    private static var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .init(identifier: "en_US")
        formatter.dateFormat = "dd.MM.yy"
        return formatter
    }

    private static var yyDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .init(identifier: "en_US")
        formatter.dateFormat = "dd.MM."
        return formatter
    }

    private static var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .init(identifier: "en_US")
        formatter.dateFormat = "HH.mm.ss"
        return formatter
    }

    func encodeHeader(to byteBuffer: inout ByteBuffer) {
        format.encode(to: &byteBuffer)

        fileInformation.subject.encode(to: &byteBuffer)
        fileInformation.recording.encode(to: &byteBuffer)

        let year = Calendar.current.component(.year, from: fileInformation.recording.startDate)
        if year >= 1985 && year <= 2084 {
            byteBuffer.writeEDFAscii(Self.dateFormatter.string(from: fileInformation.recording.startDate), length: 8)
        } else {
            // The 'startdate' and 'starttime' fields in the header should contain only characters 0-9, and the period (.)
            // as a separator, for example "02.08.51". In the 'startdate', use 1985 as a clipping date in order to avoid the Y2K problem.
            // So, the years 1985-1999 must be represented by yy=85-99 and the years 2000-2084 by yy=00-84. After 2084, yy must be 'yy'
            // and only item 4 of this paragraph defines the date (in the recording info field).
            byteBuffer.writeEDFAscii(Self.yyDateFormatter.string(from: fileInformation.recording.startDate) + "yy", length: 8)
        }

        byteBuffer.writeEDFAscii(Self.timeFormatter.string(from: fileInformation.recording.startDate), length: 8)

        byteBuffer.writeEDFAscii(headerLength, length: 8)
        byteBuffer.writeEDFAscii(dataFormat, length: 44)

        byteBuffer.writeEDFAscii(dataRecordsCount, length: 8)
        switch fileInformation._recordDuration {
        case let .integer(value):
            byteBuffer.writeEDFAscii(value, length: 8)
        case let .decimal(value):
            byteBuffer.writeEDFAsciiTrimming(value, length: 8)
        }

        byteBuffer.writeEDFAscii(channelCount, length: 4)
        signals.encode(to: &byteBuffer)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension GenericFileWriter where S == EDFSample {
    /// Create a new EDF file writer.
    /// - Parameters:
    ///   - url: The url to the file to write. Note that the file must be created already.
    ///   - format: The data records format.
    ///   - information: The file information.
    ///   - signals: The array of signal descriptions.
    /// - Throws: Throws if FileHandle creation fails.
    public convenience init(url: URL, format: RecordingFormat? = nil, information: FileInformation, signals: [Signal]) throws {
        try self.init(url: url, format: .edf, fileInformation: information, dataFormat: format?.dataFormat(for: .edf), signals: signals)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension GenericFileWriter where S == BDFSample {
    /// Create a new BDF file writer.
    /// - Parameters:
    ///   - url:  The url to the file to write. Note that the file must be created already.
    ///   - type: The file type. There is a compatibility mode of encoding BDF files via the EDF version header.
    ///   - format: The data records format.
    ///   - information: The file information.
    ///   - signals: The array of signal descriptions.
    /// - Throws: Throws if FileHandle creation fails.
    public convenience init(
        url: URL,
        type: FileFormat = .bdf,
        format: RecordingFormat? = nil,
        information: FileInformation,
        signals: [Signal]
    ) throws {
        let dataFormat = format?.dataFormat(for: type) ?? type.bdfReservedField
        try self.init(url: url, format: type, fileInformation: information, dataFormat: dataFormat, signals: signals)
    }
}
