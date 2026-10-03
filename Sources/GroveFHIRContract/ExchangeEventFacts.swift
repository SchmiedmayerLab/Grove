//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// What an event states about the converting application, its host and the participant's studies,
/// frozen at reservation so an exact redelivery rebuilds identical bytes.
///
/// Every graph is built from its reservation's facts, which are always decoded from the ledger's stored
/// entry: the first delivery and every redelivery take the same path.
package struct ExchangeEventFacts: Hashable, Sendable {
    package let application: ApplicationDevice
    package let host: HostDevice
    /// The enrollments in graph order.
    package let studies: [StudyEnrollment]

    package init(application: ApplicationDevice, host: HostDevice, studies: [StudyEnrollment]) {
        self.application = application
        self.host = host
        self.studies = studies
    }
}


extension ExchangeProducer {
    /// The facts a new reservation is minted under: this producer's, as captured when it was built.
    package var facts: ExchangeEventFacts {
        ExchangeEventFacts(application: application, host: host, studies: studies)
    }
}
