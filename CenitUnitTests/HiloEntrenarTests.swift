import XCTest
import StrandDesign
import StrandAnalytics
@testable import Cenit

/// FER-85 — el hilo de Entrenar sale del MISMO constructor que el héroe de Hoy, y estas pruebas
/// fijan las dos puertas que la revisión final encontró abiertas: la palabra-veredicto solo se
/// pronuncia con la noche anclada, y los tres estados sin veredicto no son el mismo estado.
@MainActor
final class HiloEntrenarTests: XCTestCase {

    private func read(_ verdict: Preparedness.Verdict,
                      nightAnchored: Bool,
                      autonomicPossible: Bool = true,
                      maturity: BaselineStatus = .trusted) -> Preparedness.Read {
        // `isNightAnchored` se deriva de los drivers: con dato en los dos ejes, la noche está
        // anclada; sin dato de sueño, no.
        let sleepState: Preparedness.AxisState = nightAnchored ? .inRange : .noData
        return Preparedness.Read(
            verdict: verdict,
            drivers: [.init(axis: .autonomic, state: .inRange, orientedZ: 0.2),
                      .init(axis: .sleep, state: sleepState, orientedZ: nil)],
            signals: [], signalsPresent: nightAnchored ? 2 : 1, signalsTotal: 2,
            maturity: maturity, autonomicNights: 30, trend: nil,
            autonomicPossible: autonomicPossible)
    }

    private func hilo(_ prep: Preparedness.Read?, nights: Int = 30,
                      health: Bool = true, pending: Bool = false,
                      hasPlan: Bool = true) -> LiquidHoyBuilder.HiloEntrenar? {
        LiquidHoyBuilder.hiloEntrenar(prep: prep, nights: nights, healthConnected: health,
                                      verdictPending: pending, hasPlan: hasPlan)
    }

    /// El hilo dice la MISMA palabra grande que el héroe en cada causa sin veredicto (FER-128 r13):
    /// 0…3 noches «Conociéndote», 4…∞ «Sin lectura de hoy», sin FC posible «Todavía no puedo leer
    /// tus mañanas», base rancia «Tu rango necesita noches frescas».
    func testSinVeredicto_elHiloEspejaAlHeroe() {
        func titulo(_ h: LiquidHoyModel.Hero) -> String {
            if case .demotado(_, let t, _) = h { return t }
            return "?"
        }
        for nights in [0, 3, 4, 13, 14, 30] {
            let prep = read(.lowSignal, nightAnchored: true)
            let hero = LiquidHoyBuilder.hero(prep: prep, nights: nights).0
            XCTAssertEqual(hilo(prep, nights: nights)?.palabra, titulo(hero), "noches = \(nights)")
        }
        let sinFC = read(.lowSignal, nightAnchored: true, autonomicPossible: false)
        XCTAssertEqual(hilo(sinFC, nights: 2)?.palabra,
                       titulo(LiquidHoyBuilder.hero(prep: sinFC, nights: 2).0))
        let rancia = read(.lowSignal, nightAnchored: true, maturity: .stale)
        XCTAssertEqual(hilo(rancia, nights: 30)?.palabra,
                       titulo(LiquidHoyBuilder.hero(prep: rancia, nights: 30).0))
    }

    /// La regla que el gate encontró rota: sin noche anclada, Hoy NO dice la palabra. El hilo
    /// tampoco puede decirla, o las dos pantallas hablan distinto la misma mañana.
    func testSinNocheAncladaNoSePronunciaElVeredicto() {
        for verdict: Preparedness.Verdict in [.full, .caution, .easy] {
            let h = hilo(read(verdict, nightAnchored: false))
            XCTAssertEqual(h?.tono, .hueco, "\(verdict) sin noche anclada")
            XCTAssertNotEqual(h?.palabra, LiquidHoyBuilder.palabraVeredicto(verdict),
                              "\(verdict): la palabra del héroe no puede salir sin la noche")
        }
    }

    func testConNocheAncladaDiceLaMismaPalabraQueElHeroe() {
        for verdict: Preparedness.Verdict in [.full, .caution, .easy] {
            let h = hilo(read(verdict, nightAnchored: true))
            XCTAssertEqual(h?.palabra, LiquidHoyBuilder.palabraVeredicto(verdict), "\(verdict)")
        }
    }

    /// Los tres estados sin veredicto tienen tres frases distintas: colapsarlos en «Conociéndote»
    /// le decía «te estoy conociendo» a quien nunca conectó Apple Salud.
    func testLosTresEstadosSinVeredictoNoSonElMismo() {
        let sinPermiso = hilo(nil, health: false)
        let sinReloj = hilo(read(.lowSignal, nightAnchored: false, autonomicPossible: false))
        let calibrando = hilo(nil, nights: 1)
        let sinLectura = hilo(nil, nights: 30)
        // Lo que el usuario lee es la FRASE COMPLETA: dos estados pueden compartir la palabra
        // («Sin lectura de hoy») mientras dan razones distintas, y eso es correcto — lo que no
        // puede pasar es que dos razones distintas se lean idénticas.
        let frases = [sinPermiso, sinReloj, calibrando, sinLectura].map {
            [$0?.palabra, $0?.consejo].compactMap { $0 }.joined(separator: " · ")
        }
        XCTAssertEqual(Set(frases).count, frases.count, "cada razón necesita su propia frase: \(frases)")
        for h in [sinPermiso, sinReloj, calibrando, sinLectura] {
            XCTAssertEqual(h?.tono, .hueco)
        }
    }

    /// Con el veredicto todavía calculándose, el hilo no se dibuja.
    func testConVeredictoPendienteElHiloCalla() {
        XCTAssertNil(hilo(nil, pending: true))
    }

    /// Sin plan, el consejo no puede prometer «tu plan de hoy»: sería una frase sobre algo que el
    /// usuario todavía no tiene.
    func testSinPlanElConsejoNoHablaDeUnPlan() {
        let conPlan = hilo(read(.full, nightAnchored: true), hasPlan: true)
        let sinPlan = hilo(read(.full, nightAnchored: true), hasPlan: false)
        XCTAssertNotEqual(conPlan?.consejo, sinPlan?.consejo)
        XCTAssertEqual(conPlan?.palabra, sinPlan?.palabra, "la palabra no cambia, solo el consejo")
    }

    /// La misma puerta gobierna la SUBIDA: si Hoy no pronuncia el veredicto, Entrenar no puede
    /// retener una subida por él.
    func testLaSubidaUsaLaMismaPuertaQueLaPalabra() {
        let anclada = read(.caution, nightAnchored: true)
        let sinAnclar = read(.caution, nightAnchored: false)
        XCTAssertTrue(anclada.isNightAnchored)
        XCTAssertFalse(sinAnclar.isNightAnchored)
        // Con noche: ámbar retiene. Sin noche: el veredicto no se usa, así que el plan corre.
        XCTAssertFalse(TrainingRegulation.allowsRaise(
            TrainingRegulation.advice(verdict: anclada.verdict, isPending: false)))
        XCTAssertTrue(TrainingRegulation.allowsRaise(
            TrainingRegulation.advice(verdict: nil, isPending: false)))
    }
}
