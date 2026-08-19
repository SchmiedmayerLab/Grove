//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveFoundation
import Testing


@Suite
struct DataDescriptorTests {
    @Test
    func equalBitPattern() {
        let data1 = Data([0xFF, 0x00, 0xAA])
        let data2 = Data([0xFF, 0x00, 0xAA])
        let data3 = Data([0xFF, 0x00])
        let data4 = Data([0xFF, 0x00, 0xAA, 0x00])
        #expect(DataDescriptor.equalBitPattern(lhs: data1, rhs: data2), "Identical data should be equal")
        #expect(!DataDescriptor.equalBitPattern(lhs: data1, rhs: data3), "Different length data should not be equal")
        #expect(DataDescriptor.equalBitPattern(lhs: data1, rhs: data4), "Additional zero bytes in rhs should be ignored")
    }
    
    @Test
    func dataDescriptorEquality_sameDataAndMask() {
        let data1 = Data([0xFF, 0x00, 0xAA])
        let mask1 = Data([0xFF, 0xFF, 0xFF])
        let descriptor1 = DataDescriptor(data: data1, mask: mask1)
        let descriptor2 = DataDescriptor(data: data1, mask: mask1)
        #expect(descriptor1 == descriptor2, "Data descriptors with the same data and mask should be equal")
    }
    
    @Test
    func dataDescriptorEquality_differentDataSameMask() {
        let data1 = Data([0xFF, 0x00, 0xAA])
        let data2 = Data([0xFF, 0x00, 0xBB])
        let mask1 = Data([0xFF, 0xFF, 0xFF])
        let descriptor1 = DataDescriptor(data: data1, mask: mask1)
        let descriptor2 = DataDescriptor(data: data2, mask: mask1)
        #expect(descriptor1 != descriptor2, "Data descriptors with different data but the same mask should not be equal")
    }
    
    @Test
    func dataDescriptorEquality_sameDataDifferentMask() {
        let data1 = Data([0xFF, 0x00, 0xAA])
        let mask1 = Data([0xFF, 0xFF, 0xFF])
        let mask2 = Data([0xFF, 0x00, 0xFF])
        let descriptor1 = DataDescriptor(data: data1, mask: mask1)
        let descriptor2 = DataDescriptor(data: data1, mask: mask2)
        #expect(descriptor1 != descriptor2, "Data descriptors with the same data but different masks should not be equal")
    }
    
    @Test
    func dataDescriptorEquality_bitwiseAndComparison() {
        let data1 = Data([0xFF, 0x00, 0xAA])
        let data2 = Data([0xFF, 0x00, 0xAB])
        let mask1 = Data([0xFF, 0xFF, 0xFE])
        let descriptor1 = DataDescriptor(data: data1, mask: mask1)
        let descriptor2 = DataDescriptor(data: data2, mask: mask1)
        #expect(descriptor1 == descriptor2, "Data descriptors with different data but the same masked result should be equal")
    }
    
    @Test
    func matches_sameDataAndMask() {
        let data = Data([0xFF, 0x00, 0xAA])
        let mask = Data([0xFF, 0xFF, 0xFF])
        let descriptor = DataDescriptor(data: data, mask: mask)
        #expect(descriptor.matches(data), "Data should match exactly when both the data and the mask are identical.")
    }
    
    @Test
    func matches_differentDataSameMask() {
        let data = Data([0xFF, 0x00, 0xAA])
        let otherData = Data([0xFF, 0x00, 0xAB])
        let mask = Data([0xFF, 0xFF, 0xFF])
        let descriptor = DataDescriptor(data: data, mask: mask)
        #expect(!descriptor.matches(otherData), "Data should not match when the data differs and the mask is fully applied.")
    }
    
    @Test
    func matches_maskedDataMatches() {
        let data = Data([0xFF, 0x00, 0xAA])
        let otherData = Data([0xFF, 0x00, 0xAB])
        let mask = Data([0xFF, 0xFF, 0xFE])  // Ignore the last bit of the last byte
        let descriptor = DataDescriptor(data: data, mask: mask)
        #expect(descriptor.matches(otherData), "Data should match if the masked bits are equal.")
    }
    
    @Test
    func matches_dataShorterThanDescriptor() {
        let data = Data([0xFF, 0x00, 0xAA])
        let shorterData = Data([0xFF, 0x00])
        let mask = Data([0xFF, 0xFF, 0xFF])
        let descriptor = DataDescriptor(data: data, mask: mask)
        #expect(!descriptor.matches(shorterData), "Data shorter than the descriptor should not match.")
    }
    
    @Test
    func matches_dataLongerThanDescriptor() {
        let data = Data([0xFF, 0x00, 0xAA])
        let longerData = Data([0xFF, 0x00, 0xAA, 0x00])
        let mask = Data([0xFF, 0xFF, 0xFF])
        let descriptor = DataDescriptor(data: data, mask: mask)
        #expect(descriptor.matches(longerData), "Data longer than the descriptor should match as long as the relevant bits match.")
    }
    
    @Test
    func matches_differentMasksSameData() {
        let data = Data([0xFF, 0x00, 0xAA])
        let maskedData = Data([0xFF, 0x00, 0xAB])
        let mask1 = Data([0xFF, 0xFF, 0xFE])  // Ignore the last bit of the last byte
        let mask2 = Data([0xFF, 0xFF, 0xFF])  // Fully consider all bits
        let descriptor1 = DataDescriptor(data: data, mask: mask1)
        let descriptor2 = DataDescriptor(data: data, mask: mask2)
        #expect(descriptor1.matches(maskedData), "Descriptor with mask that ignores last bit should match data with last bit difference.")
        #expect(!descriptor2.matches(maskedData), "Descriptor with fully applied mask should not match data with last bit difference.")
    }
    
    @Test
    func matches_ArraySlice() {
        let data = Data([0x02, 0x04, 0x05])
        let descriptor = DataDescriptor(data: Data([0xFF]), mask: Data([0b11001010]))
        let suffix = data[2...]
        #expect(!descriptor.matches(suffix))
    }
}
