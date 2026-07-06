import SwiftUI
import StrandDesign

/// The minimal watch face for a mirrored strength session (FER-740, F1.1). It shows only what's needed
/// to prove the loop end-to-end: elapsed time (from the session, never a local timer that could lie),
/// the watch's own pulse, and — during a rest window pushed by the iPhone — a local countdown. Polished
/// layout, haptics, and a visual summary are FER-B.
struct RestMirrorView: View {
    @EnvironmentObject var manager: WatchWorkoutManager

    private let t = InstrumentoTheme.base

    var body: some View {
        Group {
            if manager.sessionActive, let start = manager.startDate {
                session(start: start)
            } else {
                idle
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(t.paper.ignoresSafeArea())
    }

    private var idle: some View {
        VStack(spacing: 6) {
            Text("Cénit")
                .font(StrandFont.headline)
                .foregroundStyle(t.ink)
            Text("Inicia una sesión en tu iPhone")
                .font(StrandFont.caption)
                .foregroundStyle(t.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func session(start: Date) -> some View {
        VStack(spacing: 10) {
            // Elapsed — driven by the session's start, counting up.
            Text(start, style: .timer)
                .font(StrandFont.display(40))
                .foregroundStyle(t.ink)
                .monospacedDigit()

            if manager.heartRate > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill").foregroundStyle(t.dataHeart)
                    Text("\(manager.heartRate)")
                        .font(StrandFont.title2).foregroundStyle(t.ink)
                    Text("lpm").font(StrandFont.caption).foregroundStyle(t.inkSecondary)
                }
            }

            if let rest = manager.rest {
                restBanner(rest)
            }
        }
        .padding()
    }

    private func restBanner(_ rest: RestActivitySnapshot) -> some View {
        VStack(spacing: 2) {
            Text("Descanso")
                .font(StrandFont.overline).tracking(0.8)
                .foregroundStyle(t.inkTertiary)
            Text(timerInterval: rest.restStartedAt...rest.restEndsAt, countsDown: true)
                .font(StrandFont.title1)
                .foregroundStyle(t.dataStrain)
                .monospacedDigit()
        }
        .padding(.top, 2)
    }
}
