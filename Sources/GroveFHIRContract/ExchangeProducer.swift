//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// Who is exporting, one deployment, one participant, one application installation, and the ledger that
/// numbers its events.
///
/// Immutable; rebuild it when any input changes. The inputs every event shares are checked once
/// here, so a deployment fault is reported where the producer is configured rather than inside a
/// conversion. The ledger numbers every event the producer emits and freezes the application, host and
/// studies each one states, so a redelivery after a rebuild reproduces the same bytes.
///
/// Grove owns the ledger's logic and its entries; the application supplies durable, transactional storage
/// through ``Storage``. The ledger holds the producer instance and its counter, one reservation per event key
/// an exporter has not yet released, and the facts each reservation was minted under. A key that is still
/// reserved, under the same context, returns its reservation unchanged, so an exact redelivery after a crash
/// rebuilds byte-identical output. Nothing is forgotten implicitly; ``forgetReservations(madeBefore:)`` is the
/// explicit maintenance call.
///
/// Every ledger operation is one storage transaction; the producer holds no lock and no mutable state, so any
/// number of producers may share one storage. Calls block for their transaction, so keep them off the main
/// actor. See <doc:ExchangeLedgerStorage> for the contract a storage must meet.
public final class ExchangeProducer: Sendable {
    /// A configuration the producer refuses, as every event built under it would be refused.
    public enum ConfigurationError: Error, Equatable, Sendable {
        /// The subject's pseudonym is numbered in one of the deployment's own graph identity systems.
        case reservedSubjectIdentifierSystem(IdentifierSystem)
        /// A study or enrollment identifier is numbered in one of the deployment's own graph identity systems.
        case reservedStudyIdentifierSystem(IdentifierSystem)
        /// Two enrollments name the same study.
        case duplicateStudy(BusinessIdentifier)
        /// Two enrollments carry the same enrollment identifier.
        case duplicateEnrollment(BusinessIdentifier)
        /// The application, host or studies do not survive the ledger's encoding, so no event could freeze them,
        /// such as a study whose protocol canonical has an empty URL, which no canonical text states.
        case unfreezableFacts

        /// The registered diagnostic: every configuration fault is a deployment defect.
        public var diagnostic: ProducerDiagnostic {
            ExchangeGraphRule.mobileInputUnclassified.diagnostic(at: "ExchangeProducer")
        }
    }

    /// The deployment's scope that mints every opaque identity.
    package let identityScope: OpaqueIdentityScope
    /// The participant every event is about.
    package let subject: Subject
    /// The converting application, as its Device snapshot states it. Graphs state the facts their event froze,
    /// never this live value.
    package let application: ApplicationDevice
    /// The host the application runs on, as captured when the producer was built.
    package let host: HostDevice
    /// The participant's known enrollments, each study once.
    package let studies: [StudyEnrollment]
    /// The ledger the producer's events take their sequences and frozen facts from.
    let ledger: Ledger
    /// The application, host and studies as the ledger stores them, encoded once here for every reservation.
    let preparedFacts: PreparedFacts

    /// Creates the producer of one installation over the application's ledger storage.
    ///
    /// Nothing is read from `storage` here; the ledger is read, and any storage error surfaces, on first use.
    ///
    /// - Parameters:
    ///   - identityScope: The deployment's scope that mints every opaque identity.
    ///   - subject: The participant every event is about.
    ///   - application: The converting application, as its Device snapshot states it.
    ///   - host: The host the application runs on; captured now, as a later snapshot may differ.
    ///   - studies: The participant's known enrollments, each study once.
    ///   - storage: The durable storage of the ledger the producer's events take their sequences and frozen facts
    ///     from; ``InMemoryStorage`` for tests, previews and single-process tools.
    public convenience init(
        identityScope: OpaqueIdentityScope,
        subject: Subject,
        application: ApplicationDevice,
        host: HostDevice = .current(),
        studies: [StudyEnrollment] = [],
        storage: any Storage
    ) throws(ConfigurationError) {
        try self.init(
            identityScope: identityScope,
            subject: subject,
            application: application,
            host: host,
            studies: studies,
            ledger: Ledger(storage: storage, holds: .shared)
        )
    }

    /// A producer over `ledger`; tests give a ledger its own hold registry to simulate another process.
    init(
        identityScope: OpaqueIdentityScope,
        subject: Subject,
        application: ApplicationDevice,
        host: HostDevice,
        studies: [StudyEnrollment],
        ledger: Ledger
    ) throws(ConfigurationError) {
        let reserved = identityScope.systems.all
        guard !reserved.contains(subject.identifier.system) else {
            throw .reservedSubjectIdentifierSystem(subject.identifier.system)
        }
        var seenStudies: Set<BusinessIdentifier> = []
        var seenEnrollments: Set<BusinessIdentifier> = []
        for enrollment in studies {
            for identifier in [enrollment.study, enrollment.enrollment] where reserved.contains(identifier.system) {
                throw .reservedStudyIdentifierSystem(identifier.system)
            }
            guard seenStudies.insert(enrollment.study).inserted else {
                throw .duplicateStudy(enrollment.study)
            }
            guard seenEnrollments.insert(enrollment.enrollment).inserted else {
                throw .duplicateEnrollment(enrollment.enrollment)
            }
        }
        guard let preparedFacts = PreparedFacts(ExchangeEventFacts(application: application, host: host, studies: studies)) else {
            throw .unfreezableFacts
        }
        self.identityScope = identityScope
        self.subject = subject
        self.application = application
        self.host = host
        self.studies = studies
        self.ledger = ledger
        self.preparedFacts = preparedFacts
    }

    /// Forgets every entry of the ledger in one transaction.
    ///
    /// The next reservation mints a new producer instance and numbers from one, and a receipt from before the
    /// reset releases nothing. Always a safe recovery from ``LedgerError``.
    public func resetLedger() throws {
        try ledger.reset()
    }

    /// Forgets the reservations made before `cutoff`, by their reservation instant, then the facts no
    /// remaining reservation references, in one transaction.
    ///
    /// Grove never calls this itself. It costs time proportional to the ledger. The cutoff and the
    /// stored instants are on the caller's clock, so choose a cutoff that tolerates clock skew. A
    /// forgotten key that is redelivered becomes a new event, including one a live call still holds.
    ///
    /// - Returns: The number of reservations forgotten.
    @discardableResult
    public func forgetReservations(madeBefore cutoff: Date) throws -> Int {
        try ledger.forgetReservations(madeBefore: cutoff)
    }

    /// One reservation per distinct request in one ledger transaction, new ones under this producer's facts, and
    /// the receipt that ends the call's hold on them.
    ///
    /// See `Ledger.reserve(_:at:facts:)` for what a reservation keeps. The receipt exists before the caller
    /// delivers anything, so a delivery that throws drops it and its holds lapse. Releasing it also forgets
    /// `keys`, as `Ledger.finish(_:released:forgetting:)` describes; a call that reserves nothing forgets
    /// nothing. No requests touch no ledger, and their `instant` is never checked.
    package func reserve(
        _ requests: some Collection<ExchangeEventRequest>,
        at instant: Date,
        forgetting keys: [ExchangeEventKey] = []
    ) throws -> (reservations: [ExchangeEventRequest: ExchangeEventReservation], receipt: Receipt) {
        let reservations = requests.isEmpty ? [:] : try ledger.reserve(requests, at: instant, facts: preparedFacts)
        return (reservations, Receipt(ledger: ledger, held: reservations.values.map(\.handle), forgetting: keys))
    }
}
