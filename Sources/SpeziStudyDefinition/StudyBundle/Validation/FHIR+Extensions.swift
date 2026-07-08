//
// This source file is part of the Stanford Spezi open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import ModelsR4


@available(iOS 16, macOS 13, macCatalyst 16, watchOS 9, visionOS 1, *)
extension Extension.ValueX {
    var isInteger: Bool {
        switch self {
        case .integer:
            true
        default:
            false
        }
    }
    
    var isDecimal: Bool {
        switch self {
        case .decimal:
            true
        default:
            false
        }
    }
    
    var isQuantity: Bool {
        switch self {
        case .quantity:
            true
        default:
            false
        }
    }
    
    var isCoding: Bool {
        switch self {
        case .coding:
            true
        default:
            false
        }
    }
    
    var isDate: Bool {
        switch self {
        case .date:
            true
        default:
            false
        }
    }
    
    var isTime: Bool {
        switch self {
        case .time:
            true
        default:
            false
        }
    }
    
    var isDateTime: Bool {
        switch self {
        case .dateTime:
            true
        default:
            false
        }
    }
    
    var kindName: String {
        switch self {
        case .address:
            "address"
        case .age:
            "age"
        case .annotation:
            "annotation"
        case .attachment:
            "attachment"
        case .base64Binary:
            "base64Binary"
        case .boolean:
            "boolean"
        case .canonical:
            "canonical"
        case .code:
            "code"
        case .codeableConcept:
            "codeableConcept"
        case .coding:
            "coding"
        case .contactDetail:
            "contactDetail"
        case .contactPoint:
            "contactPoint"
        case .contributor:
            "contributor"
        case .count:
            "count"
        case .dataRequirement:
            "dataRequirement"
        case .date:
            "date"
        case .dateTime:
            "dateTime"
        case .decimal:
            "decimal"
        case .distance:
            "distance"
        case .dosage:
            "dosage"
        case .duration:
            "duration"
        case .expression:
            "expression"
        case .humanName:
            "humanName"
        case .id:
            "id"
        case .identifier:
            "identifier"
        case .instant:
            "instant"
        case .integer:
            "integer"
        case .markdown:
            "markdown"
        case .meta:
            "meta"
        case .money:
            "money"
        case .oid:
            "oid"
        case .parameterDefinition:
            "parameterDefinition"
        case .period:
            "period"
        case .positiveInt:
            "positiveInt"
        case .quantity:
            "quantity"
        case .range:
            "range"
        case .ratio:
            "ratio"
        case .reference:
            "reference"
        case .relatedArtifact:
            "relatedArtifact"
        case .sampledData:
            "sampledData"
        case .signature:
            "signature"
        case .string:
            "string"
        case .time:
            "time"
        case .timing:
            "timing"
        case .triggerDefinition:
            "triggerDefinition"
        case .unsignedInt:
            "unsignedInt"
        case .uri:
            "uri"
        case .url:
            "url"
        case .usageContext:
            "usageContext"
        case .uuid:
            "uuid"
        }
    }
}
