import SwiftUI
import StrandDesign

/// First-run acknowledgment gate (clickwrap). Shown over EVERYTHING — before onboarding, pairing, or
/// any Bluetooth access — until the current `Terms.currentVersion` is accepted, and again if the
/// terms materially change. The user must tick the (un-pre-checked) switch and tap Accept; the
/// accepted version is then stored locally, the on-device equivalent of a consent record.
///
/// FER-241 — migrated to «Liquid Glass · El Eje» régimen sobrio, reusing the onboarding shell
/// (`OnbShell` + `OnbOverline` / `OnbTitular` / `OnbCuerpo`) and `LiquidGlassButton`. Logic
/// unchanged: the consent toggle still gates Accept, and `onAccept` still records the version.
struct TermsGateView: View {
    let onAccept: () -> Void
    @State private var aceptado = false

    var body: some View {
        ZStack {
            LiquidColor.fondoGradient.ignoresSafeArea()

            OnbShell(indicadores: true) {
                // La marca no se traduce: es un nombre propio (mismo criterio que OnbActoPromesa).
                OnbOverline("Cénit")
                OnbTitular(Terms.title)
                    .padding(.top, LiquidSpace.s250)
                OnbCuerpo(Terms.intro)
                    .padding(.top, LiquidSpace.s400)

                VStack(alignment: .leading, spacing: LiquidSpace.s550) {
                    ForEach(Terms.points) { point in
                        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
                            Text(point.title)
                                .font(LiquidType.titulo)
                                .foregroundStyle(LiquidColor.tinta900)
                                .fixedSize(horizontal: false, vertical: true)
                            OnbCuerpo(point.body)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.top, LiquidSpace.s800)

                OnbCuerpo(Terms.fine, tono: LiquidColor.tinta500)
                    .padding(.top, LiquidSpace.s550)
            } pie: {
                HStack(alignment: .top, spacing: LiquidSpace.s300) {
                    Toggle("", isOn: $aceptado)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(LiquidColor.verdePrimario)
                        .strandAnimation(LiquidMotion.glassOut(LiquidMotion.quick), value: aceptado)
                        .accessibilityLabel(Text(Terms.consent))

                    OnbCuerpo(Terms.consent, tono: LiquidColor.tinta900)
                        .accessibilityHidden(true)
                }
                .padding(.bottom, LiquidSpace.s400)

                LiquidGlassButton(Terms.cta, variant: .primary, expands: true, action: onAccept)
                    .disabled(!aceptado)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
