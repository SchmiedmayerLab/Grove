//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import EDFFormat
import Foundation
import Testing


extension URL {
    static func createTmpFile(name: String) throws -> URL {
        let tmpDir = NSTemporaryDirectory()

        let url = try #require(NSURL.fileURL(withPathComponents: [tmpDir, name]))
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        FileManager.default.createFile(atPath: url.path, contents: nil)

        return url
    }
}


extension Date {
    static func createDate(
        year: Int? = nil,
        month: Int? = nil,
        day: Int? = nil,
        hour: Int? = nil,
        minute: Int? = nil,
        second: Int? = nil
    ) throws -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second

        let date = Calendar.current.date(from: components)
        return try #require(date)
    }
}


extension FileInformation {
    static func testFile(start startDate: Date, birthdate: Date) -> FileInformation {
        FileInformation(
            subject: .structured(PatientInformation(
                code: "P-1",
                sex: .male,
                birthdate: birthdate,
                name: "Test Patient" // tests escaping!
            )),
            recording: .structured(RecordingInformation(
                startDate: startDate,
                code: "R-1",
                investigatorCode: "I-1",
                equipmentCode: "Biopot"
            )),
            recordDuration: 1
        )
    }
}


extension Signal {
    static var testAF8EEGSignal: Signal {
        Signal(
            label: .eeg(location: .af8, prefix: .micro),
            transducerType: "test-transducer",
            prefiltering: "test-perfiltering",
            sampleCount: 5,
            physicalMinimum: -200,
            physicalMaximum: 200,
            digitalMinimum: -250,
            digitalMaximum: 250,
            reserved: "This is reserved."
        )
    }

    static var testAF7EEGSignal: Signal {
        Signal(
            label: .eeg(location: .af7, prefix: .micro),
            transducerType: "test-transducer2",
            prefiltering: "test-perfiltering2",
            sampleCount: 5,
            physicalMinimum: -202,
            physicalMaximum: 202,
            digitalMinimum: -252,
            digitalMaximum: 252,
            reserved: "This is reserved2."
        )
    }
}
