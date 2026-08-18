import XCTest
@testable import StrandAnalytics

/// FER-82 — «un solo oráculo»: Entrenar reads the SAME verdict Hoy shows, and one pure mapping turns
/// it into training advice. These tests pin the contract that makes the app stop contradicting itself:
/// the day the verdict is anything but clean, an earned raise waits — held, never lost.
///
/// The five states exist because the app is really in five situations. Two of them look identical on
/// screen (both silent) and must NOT behave alike, which is exactly what the first cut of this change
/// got wrong: `.silent` (read the body, nothing usable) lets the plan run as written, while `.pending`
/// (haven't finished reading) holds the raise for the second it takes to know.
final class SingleOracleTests: XCTestCase {

    private let allAdvice: [TrainingRegulation.Advice] = [.planAsIs, .lighter, .recover, .silent, .pending]

    // MARK: - The mapping

    func testVerdictMapsToAdvice() {
        func advice(_ v: Preparedness.Verdict?) -> TrainingRegulation.Advice {
            TrainingRegulation.advice(verdict: v, isPending: false)
        }
        XCTAssertEqual(advice(.full), .planAsIs)
        XCTAssertEqual(advice(.caution), .lighter)
        XCTAssertEqual(advice(.easy), .recover)
        XCTAssertEqual(advice(.lowSignal), .silent)
        XCTAssertEqual(advice(nil), .silent)
    }

    /// A verdict that hasn't landed yet is `.pending` whatever the (absent) verdict says — and the
    /// flag wins over the value, so a stale verdict can never leak through a cold start.
    func testPendingWinsOverTheVerdictValue() {
        for verdict: Preparedness.Verdict? in [.full, .caution, .easy, .lowSignal, nil] {
            XCTAssertEqual(TrainingRegulation.advice(verdict: verdict, isPending: true), .pending)
        }
    }

    // MARK: - Who may raise, who may speak

    /// The rule the whole epic hangs on: a verdict that advises easing off never lets the weight go up.
    func testOnlyACleanOrUnreadableDayAllowsARaise() {
        XCTAssertTrue(TrainingRegulation.allowsRaise(.planAsIs))
        XCTAssertFalse(TrainingRegulation.allowsRaise(.lighter))
        XCTAssertFalse(TrainingRegulation.allowsRaise(.recover))
        // No usable read: the app has no grounds to hold back what the log earned.
        XCTAssertTrue(TrainingRegulation.allowsRaise(.silent))
        // Not read YET: hold, rather than announce a raise the verdict is about to withhold.
        XCTAssertFalse(TrainingRegulation.allowsRaise(.pending))
    }

    /// «Con lowSignal o sin permiso, ninguna superficie de Entrenar muestra consejo ni frase» — the
    /// acceptance criterion, as a test. Silence also covers the cold-start window.
    func testSilentAndPendingSayNothing() {
        XCTAssertFalse(TrainingRegulation.speaks(.silent))
        XCTAssertFalse(TrainingRegulation.speaks(.pending))
        XCTAssertTrue(TrainingRegulation.speaks(.planAsIs))
        XCTAssertTrue(TrainingRegulation.speaks(.lighter))
        XCTAssertTrue(TrainingRegulation.speaks(.recover))
    }

    /// A held raise may only be announced by a state that can also explain itself. Silence must be
    /// total: «la subida espera» with no reason on screen is worse than saying nothing at all.
    func testOnlyASpeakingStateAnnouncesAHeldRaise() {
        XCTAssertTrue(TrainingRegulation.explainsHeldRaise(.lighter))
        XCTAssertTrue(TrainingRegulation.explainsHeldRaise(.recover))
        XCTAssertFalse(TrainingRegulation.explainsHeldRaise(.planAsIs))   // nothing is being held
        XCTAssertFalse(TrainingRegulation.explainsHeldRaise(.silent))     // nothing is being held
        XCTAssertFalse(TrainingRegulation.explainsHeldRaise(.pending))    // held, but wordlessly
    }

    /// No state ever both holds the raise and stays mute about it while it could speak; and no state
    /// speaks about a hold it isn't performing. The two predicates can't drift apart.
    func testHeldRaiseAnnouncementIsExactlyHoldAndSpeak() {
        for advice in allAdvice {
            XCTAssertEqual(TrainingRegulation.explainsHeldRaise(advice),
                           TrainingRegulation.speaks(advice) && !TrainingRegulation.allowsRaise(advice),
                           "\(advice)")
        }
    }

    /// El oráculo NO propone alternativas. Antes sí: `lightAlternative(.recover)` devolvía
    /// «movilidad · 20 min» y una fila de la pantalla la ofrecía. El dueño mandó retirar ese camino
    /// (FER-85) y el enum entero se fue con él, así que la garantía ya no puede escribirse como
    /// «nunca devuelve `.optionalLight`»: se escribe sobre el vocabulario.
    ///
    /// Los cinco casos son TODO lo que el veredicto sabe decir, y ninguno manda hacer algo distinto
    /// del plan: tres hablan, dos callan, y el más permisivo (`allowsRaise`) solo deja pasar la
    /// progresión que el plan ya traía. Un sexto caso —una alternativa, un «súbele», un «haz esto
    /// otro»— truena aquí, que es exactamente donde tiene que doler.
    func testElVocabularioDelOraculoSonCincoCasosYNingunoProponeOtraCosa() {
        XCTAssertEqual(Set(allAdvice.map(\.rawValue)),
                       ["planAsIs", "lighter", "recover", "silent", "pending"],
                       "el vocabulario del veredicto cambió: ¿alguien metió una recomendación?")
        // Ninguno de los cinco permite MÁS carga que la del plan: `allowsRaise` es permiso para la
        // progresión ya ganada, no una sugerencia de añadir nada.
        for advice in allAdvice where TrainingRegulation.allowsRaise(advice) {
            XCTAssertTrue(advice == .planAsIs || advice == .silent, "\(advice) permite subir")
        }
    }

    // MARK: - The raise actually defers

    /// Two sessions that met the goal → the raise is earned. Whether it goes through depends on today.
    private func earnedInput(deferRaise: Bool,
                             recoveryReason: TrainingRegulation.Reason? = nil)
        -> ProgressionMath.ProgressionInput {
        let met = ProgressionMath.PastSession(workingKg: 80, workSetReps: [8, 8, 8])
        return ProgressionMath.ProgressionInput(
            history: [met, met], targetReps: 8, targetSets: 3,
            sessionsToAdvance: 2, incrementKg: 2.5,
            recoveryReason: recoveryReason, deferRaise: deferRaise)
    }

    func testEarnedRaiseGoesThroughOnACleanDay() {
        let state = ProgressionMath.classify(earnedInput(deferRaise: false))
        guard case .readyToAdvance(let kg) = state else {
            return XCTFail("expected readyToAdvance, got \(state)")
        }
        XCTAssertEqual(kg, 82.5, accuracy: 0.0001)
    }

    /// Every advice that holds the raise defers it, and the earned weight is preserved — the session
    /// seeds at last time's load and the raise is offered there, one tap away.
    func testEveryHoldingAdviceDefersAndKeepsTheWeight() {
        for advice in allAdvice where !TrainingRegulation.allowsRaise(advice) {
            // El `deferRaise` sale DEL CONSEJO del bucle, no de una constante: así la prueba ata el
            // mapeo al clasificador en vez de comprobar cinco veces la misma llamada.
            let state = ProgressionMath.classify(
                earnedInput(deferRaise: !TrainingRegulation.allowsRaise(advice)))
            guard case .deferred(let kg) = state else {
                return XCTFail("\(advice) should defer, got \(state)")
            }
            XCTAssertEqual(kg, 82.5, accuracy: 0.0001, "the earned weight is preserved, not dropped")
        }
    }

    /// The states that allow a raise really do let it through — no accidental hold on a silent day.
    func testAllowingAdviceLetsTheRaiseThrough() {
        for advice in allAdvice where TrainingRegulation.allowsRaise(advice) {
            let state = ProgressionMath.classify(
                earnedInput(deferRaise: !TrainingRegulation.allowsRaise(advice)))
            guard case .readyToAdvance = state else {
                return XCTFail("\(advice) should advance, got \(state)")
            }
        }
    }

    /// Retro-compatibility: the legacy score-driven input keeps its exact behaviour. The app no longer
    /// feeds it (FER-82), but the pure API and its tests stay green.
    func testLegacyRecoveryPathIsUnchanged() {
        let deferredByScore = ProgressionMath.classify(earnedInput(deferRaise: false,
                                                                   recoveryReason: .recoveryLow))
        guard case .deferred = deferredByScore else {
            return XCTFail("recoveryLow must still defer, got \(deferredByScore)")
        }
        let clean = ProgressionMath.classify(earnedInput(deferRaise: false,
                                                         recoveryReason: .withinNormal))
        guard case .readyToAdvance = clean else {
            return XCTFail("withinNormal must still advance, got \(clean)")
        }
    }

    /// The score API is untouched and still tested — it is simply no longer wired to any screen.
    func testScoreDrivenSuggestStillWorks() {
        XCTAssertEqual(TrainingRegulation.suggest(recovery: 80)?.adjustment, .dialUp)
        XCTAssertEqual(TrainingRegulation.suggest(recovery: 50)?.adjustment, .hold)
        XCTAssertEqual(TrainingRegulation.suggest(recovery: 20)?.adjustment, .dialBack)
        XCTAssertNil(TrainingRegulation.suggest(recovery: nil))
    }

    // MARK: - The rule the UI must honour

    /// The verifiable rule of FER-82, stated as a test: there is no state in which the app both
    /// advises easing off AND lets the weight go up. If a future change breaks this, it fails here
    /// before it reaches a screen.
    func testNeverAdvisesEasingWhileAllowingARaise() {
        for advice in allAdvice where advice == .lighter || advice == .recover {
            XCTAssertFalse(TrainingRegulation.allowsRaise(advice), "\(advice) must never allow a raise")
        }
    }

    /// And the same rule from the verdict side, which is what the two screens actually share: with
    /// `caution` or `easy` on screen, no surface may show «Hoy subes».
    func testCautionAndEasyNeverGrantARaise() {
        for verdict: Preparedness.Verdict in [.caution, .easy] {
            let advice = TrainingRegulation.advice(verdict: verdict, isPending: false)
            XCTAssertFalse(TrainingRegulation.allowsRaise(advice), "\(verdict)")
            XCTAssertTrue(TrainingRegulation.speaks(advice), "\(verdict) must explain why it holds")
        }
    }
}
