//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@_spi(TestingSupport)
import ByteCoding
import ByteCodingTesting
import CoreBluetooth
@_spi(TestingSupport)
import GroveBluetooth
import GroveBluetoothServices
@_spi(TestingSupport)
import GroveDevices
@_spi(TestingSupport)
@testable public import GroveOmron
import Testing


typealias RACP = RecordAccessControlPoint<OmronRecordAccessOperand>

@Suite
struct GroveOmronTests {
    @Test
    func modelCodable() throws {
        let string = "\"SC-150\""
        let data = try #require(string.data(using: .utf8))
        let decoded = try JSONDecoder().decode(OmronModel.self, from: data)
        #expect(decoded == .sc150)
    }
    
    @Test
    func omronManufacturerData() throws {
        try testIdentity(from: OmronManufacturerData(
            timeSet: true,
            pairingMode: .pairingMode,
            streamingMode: .dataCommunication,
            servicesMode: .bluetoothStandard,
            users: [.init(id: 1, sequenceNumber: 3, recordsNumber: 8)]
        ))
        
        try testIdentity(from: OmronManufacturerData(
            timeSet: false,
            pairingMode: .transferMode,
            streamingMode: .streaming,
            servicesMode: .omronExtension,
            users: [
                .init(id: 1, sequenceNumber: 3, recordsNumber: 8),
                .init(id: 2, sequenceNumber: 0, recordsNumber: 0)
            ]
        ))
        
        try testIdentity(from: OmronManufacturerData(
            timeSet: false,
            pairingMode: .transferMode,
            streamingMode: .streaming,
            servicesMode: .omronExtension,
            users: [
                .init(id: 1, sequenceNumber: 3, recordsNumber: 8),
                .init(id: 2, sequenceNumber: 0, recordsNumber: 0),
                .init(id: 3, sequenceNumber: 5, recordsNumber: 0)
            ]
        ))
        
        try testIdentity(from: OmronManufacturerData(
            timeSet: false,
            pairingMode: .transferMode,
            streamingMode: .streaming,
            servicesMode: .omronExtension,
            users: [
                .init(id: 1, sequenceNumber: 3, recordsNumber: 8),
                .init(id: 2, sequenceNumber: 0, recordsNumber: 0),
                .init(id: 3, sequenceNumber: 5, recordsNumber: 0),
                .init(id: 4, sequenceNumber: 9, recordsNumber: 0)
            ]
        ))
    }
    
    @Test
    func omronHealthDevice() throws {
        let manufacturerData = OmronManufacturerData(pairingMode: .pairingMode, users: [.init(id: 1, sequenceNumber: 3, recordsNumber: 8)])
        
        let device = MockDevice.createMockDevice()
        device.$advertisementData.inject(AdvertisementData(manufacturerData: manufacturerData.encode()))
        
        #expect(device.manufacturerData?.pairingMode == .pairingMode)
        
        let manufacturerData0 = OmronManufacturerData(pairingMode: .transferMode, users: [.init(id: 1, sequenceNumber: 3, recordsNumber: 8)])
        device.$advertisementData.inject(AdvertisementData(manufacturerData: manufacturerData0.encode()))
        
        #expect(device.manufacturerData?.pairingMode == .transferMode)
        
        
        device.deviceInformation.$modelNumber.inject(OmronModel.bp5250.rawValue)
        
        #expect(device.model == .bp5250)
    }
    
    @Test
    func timeUpdateOnFirstNotificationBP() async throws {
        let device = OmronBloodPressureCuff.createMockDevice(state: .connecting, simulateRealDevice: true)
        
        var currentTime: CurrentTime?
        await confirmation { confirm in
            device.time.$currentTime.onWrite { time, _ in
                currentTime = time
                confirm()
            }
            device.time.$currentTime.inject(CurrentTime(time: ExactTime256(from: .now), adjustReason: .manualTimeUpdate))
            try? await Task.sleep(for: .seconds(1))
        }
        
        let writtenTime = try #require(currentTime)
        device.time.$currentTime.inject(writtenTime) // make sure we only notify once
        
        try await Task.sleep(for: .seconds(1))
    }
    
    @Test
    func timeUpdateOnFirstNotificationScale() async throws {
        let device = OmronWeightScale.createMockDevice(state: .connecting, simulateRealDevice: true)
        
        var currentTime: CurrentTime?
        await confirmation { confirm in
            device.time.$currentTime.onWrite { time, _ in
                currentTime = time
                confirm()
            }
            device.time.$currentTime.inject(CurrentTime(time: ExactTime256(from: .now), adjustReason: .manualTimeUpdate))
            try? await Task.sleep(for: .seconds(1))
        }
        
        let writtenTime = try #require(currentTime)
        device.time.$currentTime.inject(writtenTime) // make sure we only notify once
        
        try await Task.sleep(for: .seconds(1))
    }
    
    @Test
    func reportStoredRecords() throws {
        try testIdentity(from: RACP.reportStoredRecords(.allRecords))
        try testIdentity(from: RACP.reportStoredRecords(.lastRecord))
        try testIdentity(from: RACP.reportStoredRecords(.firstRecord))
        try testIdentity(from: RACP.reportStoredRecords(.greaterThanOrEqualTo(sequenceNumber: 12)))
        
        try testIdentity(of: RACP.self, from: #require(Data(hex: "0x0101"))) // Report All Records
        try testIdentity(of: RACP.self, from: #require(Data(hex: "0x010304FFFF"))) // Report greater than or equal to
        try testIdentity(of: RACP.self, from: #require(Data(hex: "0x06000101"))) // SUCCESS
        try testIdentity(of: RACP.self, from: #require(Data(hex: "0x06000106"))) // no records found
    }
    
    @Test
    func reportNumberOfStoredRecords() throws {
        try testIdentity(from: RACP.reportNumberOfStoredRecords(.allRecords))
        try testIdentity(from: RACP.reportNumberOfStoredRecords(.lastRecord))
        try testIdentity(from: RACP.reportNumberOfStoredRecords(.firstRecord))
        try testIdentity(from: RACP.reportNumberOfStoredRecords(.greaterThanOrEqualTo(sequenceNumber: 12)))
        
        try testIdentity(of: RACP.self, from: #require(Data(hex: "0x0401"))) // Report All Records
        try testIdentity(of: RACP.self, from: #require(Data(hex: "0x040304FFFF"))) // Report greater than or equal to
        try testIdentity(of: RACP.self, from: #require(Data(hex: "0x0500FFFF"))) // Response
    }
    
    @Test
    func numberOfLatestRecords() throws {
        try testIdentity(from: RACP.reportSequenceNumberOfLatestRecords())
        
        try testIdentity(of: RACP.self, from: #require(Data(hex: "0x1100FFFF"))) // Response
    }
    
    @Test
    func reportRecordsRequest() async throws {
        let service = OmronOptionService()
        
        service.$recordAccessControlPoint.onRequest { _ in
            RACP(opCode: .responseCode, operator: .null, operand: .generalResponse(.init(requestOpCode: .reportStoredRecords, response: .success)))
        }
        try await service.reportStoredRecords(.allRecords)
        
        service.$recordAccessControlPoint.onRequest { _ in
            RACP(
                opCode: .responseCode,
                operator: .null,
                operand: .generalResponse(.init(requestOpCode: .reportStoredRecords, response: .noRecordsFound))
            )
        }
        let error = try await #require(throws: RecordAccessResponseCode.self) {
            try await service.reportStoredRecords(.allRecords)
        }
        #expect(error == .noRecordsFound)
    }
    
    @Test
    func reportNumberOfStoredRecordsRequest() async throws {
        let service = OmronOptionService()
        
        service.$recordAccessControlPoint.onRequest { _ in
            RACP(opCode: .numberOfStoredRecordsResponse, operator: .null, operand: .numberOfRecords(1234))
        }
        
        let count = try await service.reportNumberOfStoredRecords(.allRecords)
        #expect(count == 1234)
        
        service.$recordAccessControlPoint.onRequest { _ in
            RACP(opCode: .numberOfStoredRecordsResponse, operator: .null, operand: .sequenceNumber(1234))
        }
        let error = try await #require(throws: RecordAccessResponseFormatError.self) {
            try await service.reportNumberOfStoredRecords(.allRecords)
        }
        #expect(error.reason == .unexpectedOperand)
    }
    
    @Test
    func reportSequenceNumberOfLatestRecords() async throws {
        let service = OmronOptionService()
        
        service.$recordAccessControlPoint.onRequest { _ in
            RACP(opCode: .omronSequenceNumberOfLatestRecordsResponse, operator: .null, operand: .sequenceNumber(1234))
        }
        
        let count = try await service.reportSequenceNumberOfLatestRecords()
        #expect(count == 1234)
        
        service.$recordAccessControlPoint.onRequest { _ in
            RACP(opCode: .omronSequenceNumberOfLatestRecordsResponse, operator: .null, operand: .numberOfRecords(1234))
        }
        
        let error = try await #require(throws: RecordAccessResponseFormatError.self) {
            try await service.reportSequenceNumberOfLatestRecords()
        }
        #expect(error.reason == .unexpectedOperand)
    }
    
    @Test
    func omronLocalNames() throws {
        let sc150 = try #require(OmronLocalName(rawValue: "BLESmart_00010112F974C431DBE2"))
        #expect(sc150.pairingMode == .transferMode)
        #expect(sc150.model.rawValue == "00010112")
        #expect(sc150.macAddress.rawValue == "F974C431DBE2")
        
        let bp7000 = try #require(OmronLocalName(rawValue: "BLEsmart_0000011F005FBFBE315B"))
        #expect(bp7000.pairingMode == .pairingMode)
        #expect(bp7000.model.rawValue == "0000011F")
        #expect(bp7000.macAddress.rawValue == "005FBFBE315B")
        
        let evolv = try #require(OmronLocalName(rawValue: "BLESmart_0000021F005FBF88C25B"))
        #expect(evolv.pairingMode == .transferMode)
        #expect(evolv.model.rawValue == "0000021F")
        #expect(evolv.macAddress.rawValue == "005FBF88C25B")
        
        let bp5250 = try #require(OmronLocalName(rawValue: "BLEsmart_00000160005FBF0CD044"))
        #expect(bp5250.pairingMode == .pairingMode)
        #expect(bp5250.model.rawValue == "00000160")
        #expect(bp5250.macAddress.rawValue == "005FBF0CD044")
    }
}

extension MockDevice: OmronHealthDevice {}
