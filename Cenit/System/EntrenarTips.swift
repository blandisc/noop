#if os(iOS)
import SwiftUI
import TipKit
import StrandTraining

// MARK: - Consejos contextuales de Entrenar (ola 1 · E12, issue 12-vocabulario-tutorial)
//
// Capa 2 del tutorial sin tour (artefacto `ola1-pantallas.html` §4): un `Tip` por concepto, sin
// reglas de aparición explícitas — cada uno se ancla con `.popoverTip(_:)` justo donde el concepto
// aparece en pantalla por primera vez, y `Tip.MaxDisplayCount(1)` lo invalida tras esa primera
// aparición (además del botón «Entendido» de `LiquidConsejoTipStyle`, que invalida al tocarlo). El
// estilo visual (tinta sobre vidrio) vive en `CenitDesign.LiquidConsejoTipStyle`, aplicado una sola
// vez en la raíz de la app (`CenitApp.swift:97`, sobre `ContentView()`) — ningún sitio de anclaje repite `.tipViewStyle(_:)`.
//
// Copy es-MX final: `docs/specs/ola1-entrenar/tips-es.md` / issue 12 tabla de consejos. Ninguna
// cadena promete que una sesión cambia el veredicto (D-Q12) — estos seis conceptos son de Entrenar,
// no del veredicto de Hoy.

/// Arranca TipKit una sola vez al lanzar la app (`CenitApp.init`). 100% on-device: TipKit persiste
/// su datastore local (qué tip ya se mostró) sin red — no rompe la regla offline del repo.
/// Ancla un consejo SOLO si `condition` — el overload de `popoverTip` que acepta un `Tip?` opcional
/// es iOS 26+, así que en iOS 17 la condición va aquí, no en el argumento (ola 1 · E12, fix build).
extension View {
    @ViewBuilder
    func popoverTipIf<T: Tip>(_ condition: Bool, _ tip: @autoclosure () -> T) -> some View {
        if condition { self.popoverTip(tip()) } else { self }
    }

}

enum EntrenarTips {
    static func configure() {
        do {
            // .immediate: cada consejo aparece tan pronto su concepto aparece en pantalla, sin
            // esperar un intervalo entre dos consejos DISTINTOS — son eventos raros (una vez por
            // concepto, nunca más), no una campaña de notificaciones que deba espaciarse.
            try Tips.configure([.displayFrequency(.immediate)])
        } catch {
            // Nunca bloquear el arranque de la app por un consejo — mismo criterio que el resto
            // del repo (p. ej. HealthKitBridge): un fallo de TipKit apaga los consejos, no la app.
            #if DEBUG
            print("EntrenarTips.configure failed: \(error)")
            #endif
        }
    }
}

/// «Serie «las que puedas»» — la primera vez que una fila de sesión muestra el chip AMRAP
/// (`HojaFilaSerie` en `RoutineSheetLiveTarjeta`, ola 1 · E7).
struct LasQuePuedasTip: Tip {
    var title: Text { Text("The as-many-as-you-can set") }
    var message: Text? {
        Text("Do every rep you can with good form and log how many you got. It counts for your records and to raise.")
    }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(1)] }
}

/// «Bajar y seguir» — la primera vez que una fila de sesión muestra el chip de escalón drop.
struct BajarYSeguirTip: Tip {
    var title: Text { Text("About drop and continue") }
    var message: Text? {
        Text("When you finish the set, drop the weight and keep going without resting. It adds volume; it doesn't count to raise or for records.")
    }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(1)] }
}

/// «Reps en reserva» — el teclado de sesión, la primera vez que se registra una serie de trabajo.
struct RepsEnReservaTip: Tip {
    var title: Text { Text("About reps in reserve") }
    var message: Text? {
        Text("How many more reps you had left when you finished. 0 means you hit failure. The app uses it to decide whether you raise.")
    }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(1)] }
}

/// «¿Qué tan duro estuvo?» — el primer recibo que trae la pregunta de esfuerzo (ola 1 · E3).
struct EsfuerzoEstimadoTip: Tip {
    var title: Text { Text("About how hard it was") }
    var message: Text? {
        Text("One tap when you finish. With minutes and effort, your session enters your load even without a watch.")
    }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(1)] }
}

/// «Semana ligera» — la primera vez que Tu Plan la muestra en el kicker del programa (ola 1 · E11).
struct SemanaLigeraTip: Tip {
    var title: Text { Text("About the light week") }
    var message: Text? {
        Text("The last week of the cycle: half the sets, the same weight. You rest without stopping training.")
    }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(1)] }
}

/// «Ritmo de subida» — la sección «Ritmo» de `ProgressionSetupScreen` (ola 1 · E5).
struct RitmoDeSubidaTip: Tip {
    var title: Text { Text("About the raise rhythm") }
    var message: Text? {
        Text("Steady raises after 2 sessions in a row met; fast after 1; by reps in reserve, it raises 1 if you had 2 to spare and waits if you hit failure.")
    }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(1)] }
}

extension View {
    /// El consejo de «las que puedas» / «bajar y seguir», anclado a la fila de sesión que YA
    /// muestra el chip de ese tipo (ola 1 · E12, ancla en `RoutineSheetLiveTarjeta`). `SetMode`
    /// (fuente de verdad tipada, no el string ya localizado) decide cuál de los dos aplica; una
    /// serie estándar no lleva consejo. TipKit garantiza «una sola vez» de forma global: el mismo
    /// `Tip` puede anclarse en los 3 sitios de `HojaFilaSerie` (ejercicio suelto, superserie,
    /// escalón) sin riesgo de mostrarse dos veces — tras cerrarlo en cualquiera, no vuelve en
    /// ninguno.
    @ViewBuilder
    func entrenarConsejoTipoSerie(_ mode: SetMode) -> some View {
        switch mode {
        case .amrap: self.popoverTip(LasQuePuedasTip())
        case .drop:  self.popoverTip(BajarYSeguirTip())
        case .standard: self
        }
    }
}
#endif
