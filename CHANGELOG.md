# Changelog

All notable changes to Cénit. Cénit is an independent, experimental project — not the WHOOP app, and
not affiliated with WHOOP. It reads a strap you own, on your own device, fully offline. Dates are
approximate; downloads are on the [Releases](https://github.com/NoopApp/noop/releases) page.

## What to expect

- **Independent, and experimental.** Treat Cénit as a capable work-in-progress rather than a finished
  product.
- **WHOOP 4.0 is the supported path.** It is tested and works end to end. WHOOP 5.0/MG is newer: live
  heart rate works today, but deeper metrics (recovery, strain, sleep) for 5/MG are still being
  figured out. Cénit always tells you what's live versus still building.
- **Your scores build over a few nights.** Live heart rate is instant; recovery, strain and sleep
  sharpen as Cénit learns your baseline. Import your WHOOP export to backfill your history instantly.
- **Everything stays on your device.** No account, no cloud, no sync.

---

## Unreleased

- **Las tarjetas de Hoy se elevan al tocarlas / Today's cards lift when you tap them.**
  **ES** — Al tocar una tarjeta de «Métricas de hoy», ahora **se eleva** un instante hacia tu dedo (una pizca de escala y el borde más marcado), en vez del oscurecido de antes. Es solo el realce al pulsar; el detalle sigue abriéndose como siempre, desde abajo.
  **EN** — Tapping a "Today's metrics" card now makes it **lift** toward your finger for an instant (a touch of scale and a stronger edge), instead of the previous dimming. It's just the press feedback; the detail still opens as before, from the bottom.
  ([Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift))

- **«Cómo amaneces tras cada deporte» llega a Cuerpo / "How you wake after each sport" lands in Body.**
  **ES** — La pestaña **Cuerpo** estrena, en «Actividad», un bloque que resume **cómo suele verse tu recuperación la mañana después de cada deporte**, comparado con tus días de descanso. Al tocarlo abre un detalle por deporte con una frase clara («después de una sesión así, sueles amanecer unos X puntos más abajo, y vuelves a tu nivel en ~N días»), cuántas sesiones lo respaldan y qué tan confiable es. Está enmarcado con honestidad: es una **asociación observada en tu propio historial, no una relación de causa** — el «Ver el método» nombra los factores que pueden confundirla. Mientras junta datos —hacen falta unas 6 sesiones de un mismo deporte— el bloque lo dice en vez de inventar un número. Todo on-device.
  **EN** — The **Body** tab gains an "Activity" block summarizing **how your recovery tends to look the morning after each sport**, compared with your rest days. Tapping it opens a per-sport detail with a plain sentence ("after a session like this you tend to wake about X points lower, climbing back in ~N days"), how many sessions back it up, and how reliable it is. It's framed honestly: a **descriptive association in your own history, not a cause** — "See the method" names the confounders. While it's gathering data — about 6 sessions of the same sport are needed — the block says so instead of inventing a number. All on-device.
  ([Cenit/Screens/ActivityRecoverySheet.swift](Cenit/Screens/ActivityRecoverySheet.swift), [Cenit/Screens/CuerpoView.swift](Cenit/Screens/CuerpoView.swift), [Packages/StrandAnalytics/Sources/StrandAnalytics/ActivityCostInputs.swift](Packages/StrandAnalytics/Sources/StrandAnalytics/ActivityCostInputs.swift))

- **Detalle de métrica con tu contexto personal / Per-metric detail with your personal context.**
  **ES** — Toca HRV, frecuencia cardiaca en reposo o frecuencia respiratoria en Cuerpo (o en Hoy) y se abre una pantalla con tu media de 7 días, tu rango normal personal, la tendencia del periodo que elijas (de semana a año) y cómo se calcula — mucho más que el número de un solo día.
  **EN** — Tap HRV, resting heart rate, or respiratory rate in Body (or Today) to open a screen with your 7-day average, your personal normal range, the trend over the period you pick (week to year), and how it's computed — far more than just today's number.
  ([Cenit/Screens/MetricDetailScreen.swift](Cenit/Screens/MetricDetailScreen.swift))

- **Hoy se lee como un instrumento: el número en tinta, el color en la palabra, y el HRV en cian / Today reads like an instrument: number in ink, color on the word, HRV in cyan.**
  **ES** — El número grande de recuperación ahora se imprime en **tipografía monoespaciada** (como la lectura de un instrumento) y va en **tinta**, no en color. El color del día lo lleva **solo la palabra del veredicto** —verde si estás listo, ámbar si vienes tensionado—, así el número y la palabra ya **no se contradicen** (se acabó el «66» ámbar bajo un «Equilibrado» verde). Además el dato de **HRV** cambió a un **cian** que se distingue claro del verde del veredicto (antes eran dos verdes que se confundían). El reloj del día se ve igual.
  **EN** — The big recovery number now prints in a **monospaced typeface** (like an instrument read-out) and sits in **ink**, not color. The day's color lives on **only the verdict word** — green when you're ready, amber when you're strained — so the number and the word can **no longer disagree** (no more amber "66" under a green "Balanced"). And the **HRV** datum moved to a **cyan** that's clearly distinct from the verdict's green (before they were two greens that blended together). The day clock looks the same.
  ([Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift), [Packages/StrandDesign/Sources/StrandDesign/Instrumento.swift](Packages/StrandDesign/Sources/StrandDesign/Instrumento.swift))

- **Tu Edad física aparece en Cuerpo, con su detalle / Your Physical age now appears in Cuerpo, with its detail.**
  **ES** — Cuerpo estrena la **Edad física**: un número que compara tu condición física con la de una persona promedio de tu edad, a partir de tu **frecuencia cardíaca en reposo** (lo que más pesa) y tu **actividad reciente**. En la sección Longevidad ves el número y, debajo, cuántos años estás **más joven** (en verde) o **por encima** (en ámbar) de tu edad real. Al tocarlo se abre una pantalla que explica **qué lo mueve**, **con qué datos se calcula** —es honesta: te dice cuántas noches lleva— y el método científico detrás (modelo Nes/HUNT). Mientras tu correa junta sus primeras 4 noches, te dice exactamente qué falta en vez de inventar un número. Es una **comparación de fitness, no tu edad biológica ni un diagnóstico médico**.
  **EN** — Cuerpo introduces **Physical age**: a number comparing your fitness with that of an average person your age, from your **resting heart rate** (which weighs most) and your **recent activity**. In the Longevity section you see the number and, below it, how many years **younger** (green) or **above** (amber) your real age you read. Tapping it opens a screen that explains **what moves it**, **which data it's computed from** — honestly: it tells you how many nights it has — and the science behind it (Nes/HUNT model). While your strap gathers its first 4 nights, it tells you exactly what's missing instead of inventing a number. It's a **fitness comparison, not your biological age or a medical diagnosis**.
  ([Cenit/Screens/FitnessAgeDetailView.swift](Cenit/Screens/FitnessAgeDetailView.swift), [Cenit/Screens/CuerpoView.swift](Cenit/Screens/CuerpoView.swift), [Packages/StrandAnalytics/Sources/StrandAnalytics/FitnessAgeSnapshot.swift](Packages/StrandAnalytics/Sources/StrandAnalytics/FitnessAgeSnapshot.swift))

- **Sincroniza tu correa jalando la pantalla de Hoy hacia abajo / Sync your strap by pulling Today down.**
  **ES** — Ahora puedes **jalar la pantalla de Hoy hacia abajo** para forzar una sincronización con tu correa, igual que en las apps que ya conoces. Sientes una **pequeña vibración** al provocarlo y aparece el indicador de carga de siempre; en cuanto arranca la sincronización el indicador se retira (no se queda girando), y la descarga del historial sigue marcándose abajo con «Sincronizando historial…». Si tu correa estaba desconectada, el jalón **intenta reconectarla** y sincroniza sola; si nunca has emparejado una correa, solo refresca lo que ya está en el teléfono. Tus números se actualizan solos cuando llegan datos nuevos.
  **EN** — You can now **pull the Today screen down** to force a sync with your strap, just like the apps you already know. You feel a **little vibration** when you trigger it and the usual loading indicator appears; the moment the sync starts the indicator goes away (it doesn't keep spinning), and the history download keeps showing below as "Syncing strap history…". If your strap was disconnected, the pull **tries to reconnect** and syncs on its own; if you've never paired a strap, it just refreshes what's already on your phone. Your numbers update on their own as new data arrives.
  ([Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift))

- **La sincronización de la WHOOP 4.0 ahora cierra en verde al alcanzar el presente / WHOOP 4.0 sync now finishes cleanly once it catches up.**
  **ES** — En algunas WHOOP 4.0, la sincronización del historial **nunca terminaba**: aunque todos tus datos sí se guardaban, la pantalla de Fuentes se quedaba en «Sincronizando…» y mostraba el aviso naranja «Sync ran long and was paused» una y otra vez. La causa: ese firmware nunca manda la señal de «historial completo», así que la app esperaba indefinidamente y cortaba a los 5 minutos. Ahora Cénit **se da cuenta solo de cuándo ya te alcanzó** —cuando los datos que llegan se reducen al goteo en vivo— y cierra la sincronización **como exitosa** (recibo verde «Recibiendo y guardando todo»). El corte de 5 minutos queda solo como red de seguridad. No había pérdida de datos: era solo que nunca se mostraba el «listo».
  **EN** — On some WHOOP 4.0 straps, the history sync **never finished**: even though all your data was being saved, the Data Sources screen stayed on "Syncing…" and showed the orange "Sync ran long and was paused" notice over and over. The cause: that firmware never sends the "history complete" signal, so the app waited indefinitely and cut off at 5 minutes. Cénit now **detects on its own when it has caught up** — when incoming data shrinks to the live drip — and completes the sync **as a success** (green "Receiving and storing everything" receipt). The 5-minute cutoff stays only as a safety net. No data was ever lost; it just never showed "done".
  ([Packages/WhoopProtocol/Sources/WhoopProtocol/CaughtUpDetector.swift](Packages/WhoopProtocol/Sources/WhoopProtocol/CaughtUpDetector.swift), [Cenit/Collect/Backfiller.swift](Cenit/Collect/Backfiller.swift), [Cenit/BLE/BLEManager.swift](Cenit/BLE/BLEManager.swift))

- **El «/100» del veredicto queda centrado, y Hoy queda más compacta / The verdict's "/100" is now centered, and Today is more compact.**
  **ES** — El **«/100»** del número del veredicto ahora va **centrado justo debajo del número** (antes colgaba a la derecha, descuadrado). Y mientras tu base apenas se afina (los primeros días, «N de 14 noches»), Hoy quedó **un poco más compacta**: la línea «Afinando con tu strap» ocupa menos y las tarjetas de «Métricas de hoy» son un pelín más bajas, para que entre más sin tanto scroll. (El tamaño del reloj del veredicto no cambió.)
  **EN** — The verdict number's **"/100"** now sits **centered right under the number** (it used to hang off to the right, off-center). And while your baseline is still settling (the first days, "N of 14 nights"), Today is **a bit more compact**: the "Tuning with your strap" line takes less room and the "Today's metrics" cards are slightly shorter, so more fits with less scrolling. (The verdict clock's size is unchanged.)
  ([Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift))

- **La gráfica de Pasos ya aparece al abrir su detalle / Steps now shows its 14-day chart.**
  **ES** — Al tocar el tile de **Pasos** en Hoy, el detalle mostraba el aviso de «sin datos» en lugar de la gráfica de tendencia, aunque el número de hoy sí salía. Pasaba cuando tus pasos venían del **sync en vivo de Apple Health** (no de una importación ni de la correa): ese sync guardaba los pasos para la cifra de hoy, pero se le olvidaba escribirlos en la tabla que alimenta la gráfica de 14 días. Ahora los guarda en ambos lados —igual que ya lo hacían la importación y la correa—, así que la gráfica se llena sola en la próxima sincronización (retroactiva a 30 días).
  **EN** — Tapping the **Steps** tile on Today showed the "no data" notice instead of the trend chart, even though today's number was there. It happened when your steps came from the **live Apple Health sync** (not an import or the strap): that sync stored steps for today's figure but forgot to write them to the table that feeds the 14-day chart. Now it writes them to both — like the import and the strap already did — so the chart fills in on the next sync (retroactive to 30 days).
  ([CenitApp/Health/HealthKitBridge.swift](CenitApp/Health/HealthKitBridge.swift))

- **Estrés: la gráfica de tendencia ya aparece / Stress: the trend chart shows up.**
  **ES** — Al tocar **Estrés** en «Métricas de hoy», la hoja de detalle se abría **sin ninguna gráfica** — era la única métrica sin una. Ahora muestra la tendencia de **«Últimos 14 días»** con la curva 0–3 (leída con un decimal), igual que recuperación, sueño, HRV y las demás. Reutiliza el mismo histórico diario que ya alimentaba el mini-sparkline del cuadro, así que no calcula nada nuevo.
  **EN** — Tapping **Stress** in "Today's metrics" opened a detail sheet with **no chart at all** — the only metric missing one. It now shows the **"Last 14 days"** trend with the 0–3 curve (read to one decimal), just like recovery, sleep, HRV and the rest. It reuses the same daily history that already fed the tile's sparkline, so nothing new is computed.
  ([Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift), [Cenit/Screens/MetricInfoSheet.swift](Cenit/Screens/MetricInfoSheet.swift))

- **Recupera el registro del strap en Ajustes / The strap log is back, in Settings.**
  **ES** — El **registro del strap** (la bitácora técnica de la conexión Bluetooth, útil para diagnosticar problemas y adjuntarla a un reporte) había desaparecido con el rediseño de En vivo. Vuelve, ahora embebido en **Ajustes → Strap**: lo ves desplazándose en vivo conforme tu banda se conecta y sincroniza, y puedes **Copiar** o **Guardar…** todo el registro con un toque. Si todavía no hay actividad, te lo dice en lugar de mostrar un recuadro vacío.
  **EN** — The **strap log** (the technical Bluetooth-connection trail you use to diagnose problems and attach to a bug report) had disappeared in the Live redesign. It's back, now embedded in **Settings → Strap**: you watch it scroll live as your strap connects and syncs, and you can **Copy** or **Save…** the whole log with one tap. If there's no activity yet, it says so instead of showing an empty box.
  ([Cenit/Screens/SettingsView.swift](Cenit/Screens/SettingsView.swift))

- **En vivo: hoja a la medida, cobertura por fuente y detalles más claros / Live: right-sized sheet, coverage by source, clearer details.**
  **ES** — Varios pulidos a la hoja de En vivo: (1) ahora **abre a la altura que necesita**, sin todo ese espacio vacío abajo; (2) el indicador **«en vivo» quedó junto a la cifra**, no flotando a la derecha; (3) la unidad de frecuencia cardiaca ahora dice **«lpm»** en español (antes «bpm»); (4) el encabezado **«REGISTROS»** ya no se corta; y (5) la tira de cobertura de 28 días ahora **distingue de dónde vino cada día**: verde = tu **correa**, azul = **solo Apple Health**, gris = **sin datos**, con su leyenda y conteos. Así ves de un vistazo cuántos días capturó realmente tu correa (antes pintaba de verde hasta los días que venían de Apple Health).
  **EN** — Several polish passes on the Live sheet: (1) it now **opens only as tall as it needs**, no empty space below; (2) the **"live" indicator sits next to the number**, not floating to the right; (3) the heart-rate unit now reads **"lpm"** in Spanish (was "bpm"); (4) the **"RECORDS"** header no longer gets cut off; and (5) the 28-day coverage strip now **shows where each day came from**: green = your **strap**, blue = **Apple Health only**, grey = **no data**, with a legend and counts. Now you can see at a glance how many days your strap actually captured (before, days from Apple Health also showed as green).
  ([Cenit/Screens/LiveView.swift](Cenit/Screens/LiveView.swift), [Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift))

- **En vivo ya no se desconecta a cada rato / Live no longer keeps flashing "disconnected".**
  **ES** — Antes, En vivo te mandaba a la pantalla de «Conecta tu correa» cada vez que la banda se desconectaba un instante —algo que pasa solo, todo el tiempo, porque la correa se conecta y desconecta para ahorrar batería—. Se sentía como que perdías la conexión a cada rato y como si tuvieras que reconectar a mano. Ahora una caída corta **deja el monitor en su lugar, en pausa** (la frecuencia cardíaca muestra «—», sin el punto verde de «en vivo»), con la etiqueta **«Reconectando…»** mientras la app se vuelve a enganchar sola en unos segundos. Solo si pasan ~15 s sin volver —porque de verdad te quitaste la banda o te alejaste— aparece el botón **«Conectar»**.
  **EN** — Live used to throw you onto the "Connect your strap" screen every time the band dropped for a moment — which happens on its own, all the time, because the strap connects and disconnects to save battery. It felt like you kept losing the connection and had to reconnect by hand. Now a short drop **keeps the monitor in place, paused** (heart rate shows "—", with no green "live" dot), labeled **"Reconnecting…"** while the app re-attaches on its own within a few seconds. Only if ~15 s pass without it returning — because you really took the strap off or walked away — does the **"Connect"** button appear.
  ([Cenit/Screens/LiveView.swift](Cenit/Screens/LiveView.swift))

- **Inicia un entrenamiento en vivo desde Entrenar / Start a live workout from the Train tab.**
  **ES** — La pestaña **Entrenar** tiene de nuevo **«Iniciar en vivo»**: arranca una sesión y mídela contra tu banda en tiempo real. Se abre una hoja clara con el **cronómetro**, tu **ritmo, promedio y pico**, y un botón **Terminar** que la califica y la guarda en tus entrenamientos (la puedes re-etiquetar después). La grabación sigue corriendo aunque cierres la hoja o cambies de pestaña — la fila muestra «Grabando» con el tiempo, y la vuelves a abrir con un tap. Si tu banda no está transmitiendo, el botón espera y te dice por qué; y si terminas sin que llegara ritmo cardiaco, te avisa en vez de quedarse callado. Recupera el cronómetro que vivía en En vivo (ahora En vivo es solo monitor).
  **EN** — The **Train** tab brings back **"Start live"**: begin a session and measure it against your strap in real time. A light sheet opens with the **stopwatch**, your **rate, average and peak**, and a **Finish** button that scores it and saves it to your workouts (you can re-label it later). Recording keeps running even if you close the sheet or switch tabs — the row shows "Recording" with the elapsed time, and a tap reopens it. If your strap isn't streaming, the button waits and tells you why; and if you finish before any heart rate arrived, it tells you instead of staying silent. It brings back the stopwatch that used to live in Live (now Live is monitor-only).
  ([CenitApp/App/RootTabView.swift](CenitApp/App/RootTabView.swift), [Cenit/Screens/LiveWorkoutSheet.swift](Cenit/Screens/LiveWorkoutSheet.swift), [Cenit/App/AppModel.swift](Cenit/App/AppModel.swift))

- **Tus latidos por minuto, ahora junto a «Métricas de hoy» / Your live beats per minute, now next to "Today's metrics".**
  **ES** — Quitamos la fila «Verlo latido a latido» del pie de Hoy y pusimos tu **pulso en vivo como una pastilla compacta** (un corazón con tus latidos por minuto) **a un lado del título «Métricas de hoy»**. Tócala y se abre el mismo monitor latido a latido de siempre — no cambió en nada. El punto late en color cuando tu banda está transmitiendo y se apaga a tinta cuando no; si no hay lectura en ese momento, muestra «—» pero sigue funcionando. Con esto Hoy queda aún más corta y cabe completa en una pantalla.
  **EN** — We removed the "See it beat by beat" row from the bottom of Today and put your **live pulse as a compact pill** (a heart with your beats per minute) **next to the "Today's metrics" title**. Tap it and the same beat-by-beat monitor opens as always — it didn't change at all. The dot beats in color while your strap is streaming and fades to ink when it isn't; if there's no reading right then, it shows "—" but still works. This makes Today even shorter, so it fits on one screen.
  ([Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift))

- **En vivo: los dos números de cada señal ahora se explican / Live: each signal's two numbers are now labeled.**
  **ES** — En la hoja de En vivo, cada señal mostraba dos números a la derecha sin decir qué eran. Ahora cada grupo tiene **encabezados de columna**: en «Capturando en vivo», los números grandes se rotulan **«registros»** (cuántas muestras llevas guardadas); en «Se completa al sincronizar», se agrega **«guardado»** sobre la hora (cuándo llegó la última vez) además de **«registros»**. Las columnas quedaron alineadas parejo. Y le dimos **más aire arriba** al título, que quedaba muy pegado a la orilla de la hoja.
  **EN** — On the Live sheet, each signal showed two numbers on the right without saying what they were. Each group now has **column headers**: under "Capturing live", the big numbers are labeled **"records"** (how many samples you've saved); under "Completes on sync", a **"saved"** label sits over the time (when it last arrived) alongside **"records"**. The columns now line up evenly. We also gave the title **more breathing room** at the top, where it sat too close to the sheet's edge.
  ([Cenit/Screens/LiveView.swift](Cenit/Screens/LiveView.swift))

- **«Cuerpo»: tus métricas en el tiempo, en una pantalla curada / "Body": your metrics over time, on one curated screen.**
  **ES** — La pestaña **Cuerpo** dejó de ser el viejo Tendencias prestado y ahora es su pantalla de verdad: un **resumen curado** —al estilo de Salud de Apple— en el mismo **papel claro «Instrumento»** que Hoy, con **color solo en el dato**. De un vistazo ves, agrupadas, las métricas que importan en el tiempo: **Recuperación** (la fila destacada arriba), **Descanso y carga** (Sueño · Esfuerzo del día · Estrés), **Vitales** (HRV · FC en reposo · Oxígeno · Frecuencia cardíaca · Respiración · Temp. de piel), **Actividad** (Pasos · Entrenamientos) y **Longevidad** (Edad física y Vitalidad, que dirán «Próximamente» hasta que estén listas). Cada fila trae su **mini-tendencia de 14 días** con su banda típica, y al tocarla se abre su detalle —el mismo que ya conoces de Hoy donde existe—. Al pie, accesos a **Comparar** y **Ver todas las métricas**. Sueño, Salud y Estrés se mudaron aquí desde *Ajustes › Más*.
  **EN** — The **Body** tab is no longer the borrowed old Trends screen — it's its real screen now: a **curated summary** — Apple-Health-Summary style — on the same **light "Instrumento" paper** as Today, with **color only on the datum**. At a glance you see your over-time metrics, grouped: **Recovery** (the highlighted row up top), **Rest & load** (Sleep · Day Strain · Stress), **Vitals** (HRV · Resting HR · Blood Oxygen · Heart Rate · Respiration · Skin Temp), **Activity** (Steps · Workouts) and **Longevity** (Physical age and Vitality, which read "Coming soon" until they're ready). Each row carries its **14-day mini-trend** with its typical band, and tapping it opens that metric's detail — the same one you know from Today where it exists. At the bottom, shortcuts to **Compare** and **See all metrics**. Sleep, Health and Stress moved here from *Settings › More*.
  ([Cenit/Screens/CuerpoView.swift](Cenit/Screens/CuerpoView.swift), [CenitApp/App/RootTabView.swift](CenitApp/App/RootTabView.swift))

- **En vivo ahora es una sola hoja / Live is now a single sheet.**
  **ES** — En vivo dejó de sentirse como una pantalla aparte: ahora se abre como una **hoja** (igual que las de métrica/esfuerzo que abres con un tap) y **todo cabe en una sola vista**, sin scroll. Para lograrlo, las tres secciones que se repetían —«Capturando en vivo», «Se completa al sincronizar» y los conteos guardados— se fundieron en **una lista de Señales**: cada renglón cuenta toda la historia de un sensor —su estado en vivo o de sincronización **y** cuántas muestras llevas guardadas—, en dos grupos claros (lo que late ahora vs. lo que llega al sincronizar). El pie de «guardado» se volvió más limpio: un chip de **iPhone** (con su hora) y otro de **iCloud**, más el botón **Verificar**. Misma información de siempre, sólo que ahora cabe de un vistazo.
  **EN** — Live no longer feels like a separate screen: it now opens as a **sheet** (like the metric/strain ones you tap into) and **everything fits in one view**, no scrolling. To get there, the three overlapping sections — "Capturing live", "Completes on sync" and the stored counts — merged into **one Signals list**: each row tells a sensor's whole story — its live or sync state **and** how many samples you've saved — in two clear groups (what's beating now vs. what arrives on sync). The "saved" footer got cleaner: an **iPhone** chip (with its time) and an **iCloud** chip, plus the **Verify** button. Same information as before, now at a glance.
  ([Cenit/Screens/LiveView.swift](Cenit/Screens/LiveView.swift), [Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift))

- **Nueva barra de 5 pestañas: Hoy · Cuerpo · Coach · Entrenar · Ajustes / New 5-tab bar: Today · Body · Coach · Train · Settings.**
  **ES** — La barra de abajo se reorganizó por completo. Antes eran Hoy · Tendencias · En vivo · Sueño · Más; ahora son **cinco pestañas más claras**: **Hoy** (tu día), **Cuerpo** (tus tendencias), **Coach** (Inteligencia, Hallazgos y Coach juntos), **Entrenar** (Respira e Intervalos) y **Ajustes**. **En vivo** dejó de ser pestaña: se abre desde Hoy, tocando «beat by beat» como hasta ahora. **Nada se perdió**: cada pantalla anterior sigue a la mano —y lo que aún no tiene casa definitiva (Sueño, Explorar, Comparar, Entrenamientos, Salud, Estrés, Apple Health, Fuentes de datos, Automatizaciones y Apoyo) vive por ahora en **Ajustes › Más**, hasta que cada una llegue a su lugar final. La «Barra de instrumento» se conserva tal cual: bajo Hoy sigue siendo papel cálido que respira con la hora; bajo las demás, el panel oscuro. Es el primer paso de un rediseño de navegación más grande.
  **EN** — The bottom bar was fully reorganized. It used to be Today · Trends · Live · Sleep · More; now it's **five clearer tabs**: **Today** (your day), **Body** (your trends), **Coach** (Intelligence, Insights and Coach together), **Train** (Breathe and Intervals) and **Settings**. **Live** is no longer a tab — it opens from Today by tapping "beat by beat," just like before. **Nothing was lost**: every previous screen is still reachable, and the ones without a final home yet (Sleep, Explore, Compare, Workouts, Health, Stress, Apple Health, Data Sources, Automations and Support) live for now under **Settings › More**, until each lands in its final place. The «Instrumento» bar is unchanged: under Today it's still warm paper that breathes with the hour; under the rest, the dark panel. This is the first step of a larger navigation redesign.
  ([CenitApp/App/RootTabView.swift](CenitApp/App/RootTabView.swift))

- **Hoy cabe en una sola pantalla / Today fits on one screen.**
  **ES** — Hoy se había vuelto larga: había que hacer scroll para verlo todo. La acomodamos para que entre de una: **«Verlo latido a latido» se bajó al pie** de la pantalla (antes quedaba a media altura, partiendo el héroe), las **tiles de «Métricas de hoy» son más bajas**, y **quitamos de Hoy la sección «Fuentes»** —que ya vive en Fuentes de datos / Ajustes—. El número grande, el reloj de 24 horas y el veredicto quedan igual; sólo respira mejor y, en la mayoría de los iPhones, se ve completa sin scroll.
  **EN** — Today had grown tall — you had to scroll to see all of it. We tightened the layout so it fits at a glance: **"See it beat by beat" moved to the bottom** of the screen (it used to sit mid-screen, breaking up the hero), the **"Today's metrics" tiles are shorter**, and we **removed the "Sources" section from Today** — it already lives in Data Sources / Settings. The big number, the 24-hour clock and the verdict are unchanged; it just breathes better and, on most iPhones, shows complete without scrolling.
  ([Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift))

- **Captura en vivo más fluida y a prueba de carreras / Smoother, race-safe live capture.**
  **ES** — Mientras tu banda transmite en vivo (~2 lecturas por segundo), la app decodificaba el mismo paquete hasta **3 veces** y lo hacía en el mismo hilo que dibuja la pantalla, lo que podía sentirse como pequeños tirones. Ahora cada paquete se decodifica **una sola vez**, y el trabajo pesado de decodificación de la captura se movió **fuera del hilo de la interfaz**, así que la pantalla en vivo se siente más fluida. Por dentro, además, se cerró una **carrera latente** en el decodificador (su tabla de protocolo ahora se prepara una sola vez, de forma segura entre hilos) que podía provocar fallas intermitentes. Mismos datos, misma precisión — solo más estable y fluido. (Es la base de una mejora mayor de estabilidad del Bluetooth que sigue en camino.)
  **EN** — While your strap streams live (~2 readings per second), the app was decoding the same packet up to **3×** and doing it on the same thread that draws the screen, which could feel like small stutters. Now each packet is decoded **once**, and the heavy capture-decoding work moved **off the UI thread**, so the live screen feels smoother. Under the hood it also closes a **latent race** in the decoder (its protocol table is now prepared a single time, thread-safely) that could cause intermittent glitches. Same data, same accuracy — just more stable and smooth. (This is the groundwork for a larger Bluetooth-stability improvement still on the way.)
  ([Cenit/BLE/BLEManager.swift](Cenit/BLE/BLEManager.swift), [Cenit/Collect/Collector.swift](Cenit/Collect/Collector.swift), [Packages/WhoopProtocol/Sources/WhoopProtocol/Schema.swift](Packages/WhoopProtocol/Sources/WhoopProtocol/Schema.swift))

- **En vivo, aún más limpio / Live, even cleaner.**
  **ES** — Seguimos puliendo **En vivo** como monitor puro: quitamos tres cosas que duplicaban información o ya no encajaban ahí. (1) La **batería de la correa** —ya se ve en Ajustes—. (2) El **bloque de entrenamiento** (el botón «Iniciar entrenamiento» y la tarjeta de grabación); registrar entrenamientos vive en *Más › Workouts*. (3) El renglón **«N noches guardadas en tu iPhone»** del recibo de datos —esa cuenta ya aparece en otro lugar—; el respaldo en iCloud se queda. Todo lo demás del monitor sigue igual.
  **EN** — We kept polishing **Live** as a pure monitor by removing three things that duplicated info or no longer belonged. (1) The **strap battery** — it's already in Settings. (2) The **workout block** (the "Start workout" button and the recording card); logging workouts lives in *More › Workouts*. (3) The **"N nights stored on your iPhone"** line in the data receipt — that count already shows elsewhere; the iCloud backup line stays. Everything else in the monitor is unchanged.
  ([Cenit/Screens/LiveView.swift](Cenit/Screens/LiveView.swift))

- **«Métricas de hoy»: la lectura del día, de un vistazo / "Today's metrics": your day at a glance.**
  **ES** — En Hoy, la lista de «Métricas clave» mostraba la **tendencia de 14 días** de cada métrica (una minigráfica). Pero Hoy es la **foto del día**, no la tendencia. Ahora esa sección es una **rejilla de 8 tiles** —Esfuerzo del día, Sueño, HRV, Frecuencia cardíaca, FC en reposo, Oxígeno en sangre, Pasos y **Estrés** (nuevo)— donde cada tile muestra su **valor de hoy** en su color y, debajo, **cuánto cambió respecto a ayer** (verde si mejoró, rojo si empeoró, según la métrica). La recuperación no se repite aquí: ya es el número grande de arriba. ¿Quieres la tendencia de 14 días? Sigue ahí: **toca cualquier tile** y la verás dentro, junto a su explicación. El tile de Estrés ahora también abre su propia ficha, con sus bandas 0–3 y cómo se calcula.
  **EN** — On Today, the "Key Metrics" list showed each metric's **14-day trend** (a tiny chart). But Today is the **snapshot of your day**, not the trend. That section is now a **grid of 8 tiles** — Day Strain, Sleep, HRV, Heart Rate, Resting HR, Blood Oxygen, Steps and **Stress** (new) — where each tile shows its **today's value** in its color and, below it, **how much it changed since yesterday** (green if it improved, red if it worsened, per metric). Recovery isn't repeated here: it's already the big number up top. Want the 14-day trend? It's still there: **tap any tile** and you'll see it inside, alongside its explanation. The Stress tile now opens its own card too, with its 0–3 bands and how it's computed.
  ([Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift), [Cenit/Screens/MetricInfoSheet.swift](Cenit/Screens/MetricInfoSheet.swift))

- **En vivo ahora es un monitor en papel claro, sin estorbos / Live is now a clean, light-paper monitor.**
  **ES** — La pantalla **En vivo** estaba en oscuro y mezclaba el monitor del corazón con la gestión de la correa (escanear, vibrar, desconectar, elegir modelo, el registro técnico) y un número de «carga». Ahora es un **monitor puro** en el mismo **papel claro «Instrumento»** que Hoy: el ECG y los latidos por minuto en color de corazón, los indicadores de «en vivo» y «guardado» en verde, y todo lo demás en tinta. Se conserva lo que te gusta —ECG + bpm, latidos de la sesión y su tacograma, lo que se captura en vivo, lo que se completa al sincronizar, el aviso de «todo guardado» y el recibo de datos con la cobertura de 28 días—. Salió la **carga** (vive en Hoy) y la **gestión de la correa** (se va a Ajustes). Cuando no hay correa conectada, En vivo muestra un único botón **«Conectar»**, sin callejones sin salida.
  **EN** — The **Live** screen was dark and mixed the heart monitor with strap management (scan, buzz, disconnect, pick model, the technical log) and a "strain" number. It's now a **pure monitor** on the same **light "Instrumento" paper** as Today: the ECG and beats-per-minute in heart color, the "live" and "saved" indicators in green, and everything else in ink. What you like stays — ECG + bpm, beats this session and its tachogram, what's capturing live, what completes on sync, the "everything saved" note, and the data receipt with its 28-day coverage. **Strain** is gone (it lives on Today) and **strap management** moves to Settings. When no strap is connected, Live shows a single **"Connect"** button — no dead ends.
  ([Cenit/Screens/LiveView.swift](Cenit/Screens/LiveView.swift), [Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift))

- **La sincronización ya no se queda pegada en «Sincronizando…» / Sync no longer gets stuck on "Syncing…".**
  **ES** — En un caso raro, la banda podía seguir mandando datos sin avisar nunca que ya terminó, y la app se quedaba con el mensaje **«Sincronizando…»** pegado para siempre; en otro, si el almacenamiento del teléfono no arrancaba a la primera, podías quedar **conectado pero sin guardar nada**. Ahora la sincronización tiene un **tope de tiempo**: si se alarga de más, se pausa sola, te avisa con honestidad («se pausó, continúa en la próxima») y **retoma justo donde se quedó** —no se pierde nada—. Y si el almacenamiento falla al iniciar, la app **se recupera sola en el siguiente intento** en vez de quedarse muerta. Se siente menos «congelada».
  **EN** — In a rare case the strap could keep sending data without ever signaling it had finished, leaving the app stuck on **"Syncing…"** forever; in another, if the phone's storage failed to start on the first try, you could end up **connected but saving nothing**. Sync now has a **time cap**: if it runs too long it pauses itself, tells you honestly ("paused, it'll continue next sync") and **resumes right where it left off** — nothing is lost. And if storage fails to start, the app **recovers on the next attempt** instead of staying dead. It feels less "frozen."
  ([Cenit/BLE/BLEManager.swift](Cenit/BLE/BLEManager.swift))

- **Tu banda vuelve a sincronizar al reconectar, sin intentos dobles / Your strap syncs again on reconnect, without double attempts.**
  **ES** — Se corrigieron dos fallas de la conexión con la banda. La primera: si la app volvía al frente con la banda **ya conectada**, a veces se quedaba «conectada pero sin sincronizar» —sin bajar datos nuevos— hasta que pasaba el siguiente ciclo automático (hasta 15 minutos). La segunda: al **cambiar de modelo de banda** (de una WHOOP 4 a una 5/MG o al revés), la app lanzaba **dos** intentos de conexión encimados en vez de uno. Ahora, reabrir la app con la banda conectada **rearranca el saludo y vuelve a pedir tus datos** de inmediato, y cambiar de banda hace **un solo** intento limpio.
  **EN** — Two strap-connection glitches are fixed. First: if the app came back to the foreground with the strap **already connected**, it could get stuck "connected but not syncing" — pulling no new data — until the next automatic cycle (up to 15 minutes). Second: **switching strap model** (a WHOOP 4 to a 5/MG or back) fired **two** overlapping connection attempts instead of one. Now, reopening the app while connected **restarts the handshake and re-requests your data** right away, and switching straps makes **one** clean attempt.
  ([Cenit/BLE/BLEManager.swift](Cenit/BLE/BLEManager.swift))

- **Explorar métricas ya no cierra la app / Exploring metrics no longer crashes the app.**
  **ES** — En la pestaña **Más → Explore**, abrir el detalle de una métrica cerraba la app de golpe. Era un choque entre dos pantallas que abrían su propia navegación, una dentro de otra. Lo reescribimos al patrón correcto —una sola navegación por pestaña— así que ahora **Más → Explore → tocar una métrica** abre el detalle sin cerrarse, y el botón de regresar te lleva de vuelta paso a paso (métrica → Explore → lista de Más).
  **EN** — On the **More → Explore** tab, opening a metric's detail crashed the app. It was a clash between two screens each opening their own navigation, one inside the other. We rewrote it to the correct pattern — a single navigation per tab — so now **More → Explore → tap a metric** opens the detail without crashing, and Back takes you step by step (metric → Explore → More list).
  ([Cenit/Screens/MetricExplorerView.swift](Cenit/Screens/MetricExplorerView.swift), [CenitApp/App/RootTabView.swift](CenitApp/App/RootTabView.swift))

- **Hoy ya no se traba con mucha historia / Today no longer stutters with a long history.**
  **ES** — Con muchos meses o años de datos, la pantalla de Hoy podía sentirse pesada: el scroll se trababa y, mientras llegaba tu pulso en vivo, la app a veces se congelaba lo suficiente como para cerrarse sola. Era porque Hoy volvía a calcular tu veredicto del día —ordenando toda tu historia— **muchas veces por cada cuadro de animación**. Ahora ese cálculo se hace **una sola vez cuando tus datos cambian** y se reutiliza, así que Hoy se mantiene fluido por más historia que tengas, sin cambiar ni un número de lo que ves.
  **EN** — With many months or years of data, the Today screen could feel heavy: scrolling stuttered and, while your live heart rate streamed in, the app sometimes froze long enough to quit on its own. That was because Today recomputed your day's verdict — sorting your whole history — **many times per animation frame**. That work now runs **once when your data changes** and is reused, so Today stays smooth no matter how much history you have, without changing a single number you see.
  ([Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift))

- **Cénit trabaja más liviano en segundo plano / Cénit runs lighter in the background.**
  **ES** — El cálculo que Cénit hace solo cada 15 minutos para armar tus scores (recuperación, esfuerzo, sueño) ahora **se detiene cuando cierras la app** y se reanuda al volver, en vez de seguir corriendo siempre; y **ya no compite** con la sincronización de tu banda mientras está bajando datos. Además, cuando **no llegó nada nuevo** desde la última vez, se **salta el trabajo pesado** en lugar de releer ~3 semanas de datos cada vuelta. Se traduce en menos batería y una app más fluida —con **exactamente los mismos scores** de siempre.
  **EN** — The work Cénit runs on its own every 15 minutes to build your scores (recovery, strain, sleep) now **pauses when you close the app** and resumes when you return, instead of running forever; and it **no longer competes** with your strap's sync while it's offloading data. And when **nothing new** has arrived since last time, it **skips the heavy work** instead of re-reading ~3 weeks of data every cycle. That means less battery use and a smoother app — with **exactly the same scores** as before.
  ([Cenit/App/AppModel.swift](Cenit/App/AppModel.swift), [Cenit/Data/IntelligenceEngine.swift](Cenit/Data/IntelligenceEngine.swift))

- **Tendencias se desplaza más suave, sobre todo con años de historial / Trends scrolls more smoothly, especially with years of history.**
  **ES** — Al desplazar o animar **Tendencias**, la app rehacía todo el cálculo de tus series y volvía a interpretar cada fecha **en cada cuadro**, lo que provocaba tirones cuando tienes un historial largo importado. Ahora ese trabajo se hace **una sola vez** por cada cambio de datos o de rango (semana/mes/3M…) y se reutiliza mientras nada cambie, así que el scroll y las animaciones quedan fluidos. Es el mismo contenido y los mismos números; solo se siente más ligero. De paso, varias pantallas (Hoy, Salud de Apple, Comparar, Explorador de métricas) dejaron de crear formateadores de fecha/número repetidamente al dibujar.
  **EN** — When you scrolled or animated **Trends**, the app re-did all of your series math and re-parsed every date **on every frame**, which caused stutter when you have a long imported history. That work now happens **once** per data or range change (week/month/3M…) and is reused while nothing changes, so scrolling and animations stay smooth. Same content and same numbers — it just feels lighter. Along the way, several screens (Today, Apple Health, Compare, Metric Explorer) stopped re-creating date/number formatters while drawing.
  ([Cenit/Screens/TrendsView.swift](Cenit/Screens/TrendsView.swift))

- **El héroe de Hoy ahora es un solo instrumento, centrado / Today's hero is now a single, centered instrument.**
  **ES** — En Hoy, el número del día y el reloj de 24 horas estaban uno al lado del otro, con el reloj pequeño y pegado a una orilla; se veía descentrado y a medio armar, sobre todo cuando aún falta la lectura de hoy. Ahora son **un solo instrumento**: el reloj crece y se centra en la pantalla, y el **número vive en su centro** (o un guion «—» cuando todavía no hay lectura). El punto de «ahora» sigue corriendo por el aro. Es el mismo dato y la misma escala «/100» —solo que ahora todo queda alineado y equilibrado—, en los cuatro estados de Hoy (veredicto, base de Apple Salud, calibrando y en espera).
  **EN** — On Today, the day's number and the 24-hour clock sat side by side, with the clock small and pushed to one edge; it looked off-center and half-built, especially before today's reading arrives. They're now **one instrument**: the clock grows and centers on screen, and the **number lives at its center** (or a "—" dash when there's no reading yet). The "now" dot still travels along the ring. Same datum and same "/100" scale — just aligned and balanced now — across all four Today states (verdict, Apple Health base, calibrating and waiting).
  ([Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift))

- **El dial de Hoy ahora tiene color / Today's dial now has color.**
  **ES** — El reloj de 24 horas del héroe de Hoy —el que marca la hora, tu ventana de sueño y el amanecer/atardecer— dejó de ser todo gris y ahora tiene color, como el icono de Cénit: el **arco del día** se dibuja en **ámbar**, la **banda de sueño** en **índigo** y el **punto de «ahora»** en **verde**, con la marca del mediodía en tinta. Como el resto de Hoy, el dial se entibia y atenúa con la hora —amanecer, mediodía, atardecer, noche—, así que de día luce vivo y de noche se calla. La forma del dial no cambió: es el mismo reloj, ahora a color.
  **EN** — The 24-hour clock in the Today hero — the one that marks the time, your sleep window and sunrise/sunset — is no longer all gray; it now has color, like the Cénit app icon: the **day arc** is drawn in **amber**, the **sleep band** in **indigo** and the **"now" dot** in **green**, with the noon mark in ink. Like the rest of Today, the dial warms and dims with the time of day — dawn, midday, dusk, night — so it looks vivid by day and quiets at night. The dial's shape didn't change: same clock, now in color.
  ([Packages/StrandDesign/Sources/StrandDesign/DiurnalDial.swift](Packages/StrandDesign/Sources/StrandDesign/DiurnalDial.swift))

- **Las métricas de Hoy ahora se ven que se pueden tocar / Today's metrics now look tappable.**
  **ES** — Cada renglón de «Métricas clave» (Esfuerzo, Sueño, HRV, Frecuencia cardíaca…) abría un detalle al tocarlo, pero nada lo anunciaba. Ahora muestran una pequeña **flecha** a la derecha que invita a tocar, y el renglón se **atenúa levemente** mientras lo mantienes presionado, como respuesta al toque. La flecha aparece también en métricas sin lectura de hoy (el detalle existe igual) y se entibia con el tono de la hora, igual que el resto de la pantalla. Para VoiceOver, cada renglón se anuncia como **botón** que «Abre el detalle».
  **EN** — Each "Key Metrics" row (Strain, Sleep, HRV, Heart rate…) already opened a detail on tap, but nothing said so. They now show a small **chevron** on the right inviting a tap, and the row **dims slightly** while you hold it, as touch feedback. The chevron also shows on metrics with no reading today (the detail still exists) and warms with the time of day, like the rest of the screen. For VoiceOver, each row is announced as a **button** that "Opens the detail."
  ([Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift), [Packages/StrandDesign/Sources/StrandDesign/MetricRow.swift](Packages/StrandDesign/Sources/StrandDesign/MetricRow.swift))

- **La ficha «¿Por qué este veredicto?» ahora es clara, a juego con Hoy / The "Why this verdict?" card is now light, matching Today.**
  **ES** — La ficha que se abre al tocar la **«i»** junto a la palabra del veredicto en Hoy —la que explica por qué tu día es verde, ámbar o rojo— estaba todavía en oscuro y desentonaba con la pantalla. Ahora vive en el mismo **papel claro «Instrumento»** y se entibia con la hora del día, igual que el resto de Hoy. Los colores del chip y de la leyenda son **los mismos que el número del veredicto** arriba, así que la ficha y el héroe ya nunca se contradicen. Quedó completa en español, inglés y alemán.
  **EN** — The card that opens when you tap the **"i"** next to the verdict word on Today — the one explaining why your day is green, amber or red — was still dark and clashed with the screen. It now lives on the same **light "Instrumento" paper** and warms with the time of day, like the rest of Today. The chip and legend colors are **the same as the verdict number** above, so the card and the hero never contradict each other. Fully localized in Spanish, English and German.
  ([Cenit/Screens/WhyVerdictSheet.swift](Cenit/Screens/WhyVerdictSheet.swift))

- **La barra de pestañas ya no tapa el último componente / The tab bar no longer hides the last component.**
  **ES** — Al hacer scroll hasta abajo en cualquier pestaña, el último componente quedaba parcialmente escondido detrás de la «Barra de instrumento» y había que subir para verlo (en Hoy, la tarjeta de Fuentes). Ahora cada pestaña reserva el alto exacto de la barra, así que el contenido topa con holgura por encima de ella. Aplica a Hoy y a las demás pestañas.
  **EN** — Scrolling to the bottom of any tab left the last component partly hidden behind the «Barra de instrumento», so you had to scroll up to see it (on Hoy, the Sources card). Each tab now reserves the bar's exact height, so content rests comfortably above it. Applies to Hoy and the other tabs.
  ([CenitApp/App/RootTabView.swift](CenitApp/App/RootTabView.swift))

- **La barra de pestañas se vuelve un instrumento que cambia con la hora / The tab bar becomes an instrument that shifts with the hour.**
  **ES** — La barra inferior dejó de ser una pieza oscura con el ícono verde y ahora habla el mismo idioma que la app: bajo **Hoy** se viste del papel cálido de «Instrumento diurno» y se entibia y atenúa con la hora del día —amanecer, mediodía, atardecer, noche— igual que la pantalla; bajo Tendencias, En vivo, Sueño y Más se mantiene oscura, a tono con esas pantallas. La pestaña activa ya no se pinta de verde: se marca con tinta más fuerte y un pequeño punto de «ahora». Los íconos se rehicieron de trazo fino, con un **dial de 24 horas** para Hoy (guiño al icono de Cénit) y una **luna** para Sueño.
  **EN** — The bottom bar is no longer a dark slab with a green icon; it now speaks the app's language: under **Hoy** it wears the warm "daytime instrument" paper and warms and dims with the time of day — dawn, midday, dusk, night — just like the screen; under Trends, Live, Sleep and More it stays dark, of a piece with those screens. The active tab is no longer painted green: it's marked with stronger ink and a small "now" dot. The icons were redrawn as thin strokes, with a **24-hour dial** for Hoy (echoing the Cénit app icon) and a **crescent moon** for Sleep.
  ([CenitApp/App/InstrumentTabBar.swift](CenitApp/App/InstrumentTabBar.swift), [CenitApp/App/RootTabView.swift](CenitApp/App/RootTabView.swift), [Packages/StrandDesign/Sources/StrandDesign/DialTabGlyph.swift](Packages/StrandDesign/Sources/StrandDesign/DialTabGlyph.swift))

- **Hoy: un mismo molde para todos los estados, y el número honesto cuando aún no hay veredicto / Today: one skeleton for every state, and an honest number when there's no verdict yet.**
  **ES** — La pantalla de Hoy ya mostraba un número dominante con su dial de 24 h; ahora **todos** los estados del héroe —con veredicto, calibrando, base sembrada por Apple Salud, y sin lectura— comparten el **mismo molde** (overline + número + dial + cuerpo + pie). Lo único que cambia es el número y su color: tu recuperación **en color** cuando la lectura de hoy está lista; un **«2/4»** mientras se afina tu base; o un **guion «—» en gris** cuando aún estás en espera. Y se corrigió un caso sutil: cuando hay número pero **todavía no hay contexto** para una palabra de veredicto, el número ahora se muestra **en gris** con una nota honesta («aún sin contexto suficiente»), en vez de pintarse en verde/ámbar como si fuera un veredicto firme. Misma información de siempre, una sola forma coherente.
  **EN** — The Today screen already led with a dominant number and its 24-hour dial; now **every** hero state — with a verdict, calibrating, an Apple-Health-seeded baseline, and no reading yet — shares the **same skeleton** (overline + number + dial + body + foot). Only the number and its color change: your recovery **in color** when today's reading is ready; a **"2/4"** while your baseline sharpens; or a **gray dash "—"** while you're still waiting. And a subtle case was fixed: when there's a number but **not enough context** for a verdict word, the number now shows **in gray** with an honest note ("not enough context yet") instead of being painted green/amber as if it were a firm verdict. Same information as before, one coherent shape.
  ([Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift))

- **Hoy se ve más grande, llena la pantalla y vuelve a mostrar tus fuentes / Today reads bigger, fills the screen, and shows your sources again.**
  **ES** — Segunda pasada sobre el rediseño de **Hoy**: una escala más generosa y armoniosa que **llena el espacio** que antes quedaba vacío abajo —el número del veredicto más grande, "Métricas clave" con más presencia, y cada métrica con **renglones más altos y gráficas de 14 días más grandes**—, sin que ninguna etiqueta se recorte (los nombres largos como "Oxígeno en sangre" se ven completos). El puntito del pulso en vivo quedó **centrado** con su número. La **barra de estado** (hora, señal, batería) por fin se ve en **tinta oscura** sobre el papel claro de Hoy. Y, hasta abajo, vuelve una sección **"Fuentes"** discreta que resume de dónde vienen tus datos —tu banda WHOOP y Apple Salud— sin repetir la hora de sincronización que ya está arriba.
  **EN** — A second pass over the **Today** redesign: a more generous, harmonious scale that **fills the space** that used to sit empty at the bottom — a larger verdict number, a stronger "Key Metrics" heading, and each metric with **taller rows and bigger 14-day charts** — without ever truncating a label (long names like "Blood oxygen" show in full). The live-pulse dot is now **centered** with its number. The **status bar** (clock, signal, battery) finally shows in **dark ink** on Today's light paper. And, at the very bottom, a quiet **"Sources"** section returns to summarize where your data comes from — your WHOOP strap and Apple Health — without repeating the sync time already shown up top.
  ([Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift), [Packages/StrandDesign/Sources/StrandDesign/MetricRow.swift](Packages/StrandDesign/Sources/StrandDesign/MetricRow.swift))

- **El texto de la app ya no menciona Android: Cénit habla solo de iOS / The app's copy no longer mentions Android: Cénit talks only about iOS.**
  **ES** — Limpieza de textos: como Cénit ahora es solo para iOS, quitamos las menciones a «Android» (y a «Mac») que quedaban sueltas en el texto que ves. La tarjeta de **Apoyo**, el aviso al **exportar/importar** tus datos y los **Términos de uso** ahora dicen «iOS» o simplemente «Cénit», en español, inglés y alemán. Es solo un ajuste de redacción: no cambia nada de lo que la app hace, y los Términos no requieren que los vuelvas a aceptar.
  **EN** — A copy cleanup: since Cénit is now iOS-only, we removed the leftover mentions of "Android" (and "Mac") in the text you see. The **Support** card, the **export/import** notice for your data, and the **Terms of Use** now read "iOS" or simply "Cénit," in Spanish, English and German. It's wording only — nothing the app does changes, and the Terms don't need re-accepting.
  ([Cenit/Screens/SupportView.swift](Cenit/Screens/SupportView.swift), [Cenit/Screens/SettingsView.swift](Cenit/Screens/SettingsView.swift), [TERMS.md](TERMS.md))
- **Las fichas de detalle de cada métrica ahora son claras y están en español / Each metric's detail card is now light and in Spanish.**
  **ES** — Cuando tocas una métrica en **«Métricas clave»** se abre una ficha que la explica; ahora esa ficha vive en el mismo **papel claro «Instrumento»** que la pantalla de Hoy (antes era oscura y desentonaba) y **todo su texto está en español** —el párrafo que explica qué es, las zonas (Reposo / ligero, Moderado, Intenso, Extremo…), las notas y el método—, antes en inglés. Cada ficha usa el **color de su métrica**, resalta tu zona actual y mantiene legibles las gráficas sobre el papel. Si una lectura puede venir de **Apple Salud** y aún no la conectas, la ficha te lo dice con una línea para conectarla desde Hoy. Cubre Esfuerzo del día, Sueño, HRV, Frecuencia cardíaca, FC en reposo, Oxígeno en sangre, Pasos y Recuperación (también en alemán).
  **EN** — Tapping a metric in **"Key Metrics"** opens a card that explains it; that card now lives on the same **light "Instrumento" paper** as the Today screen (it used to be dark and clashed) and **all of its text is now localized** — the paragraph explaining what it is, the zones (Rest / Light, Moderate, Hard, Extreme…), the notes and the method — previously in English. Each card uses its **metric's color**, highlights your current zone, and keeps its charts legible on the paper. If a reading can come from **Apple Health** and you haven't connected it yet, the card says so with a line to connect it from Today. Covers Day Strain, Sleep, HRV, Heart Rate, Resting HR, Blood Oxygen, Steps and Recovery (German too).
  ([Cenit/Screens/MetricInfoSheet.swift](Cenit/Screens/MetricInfoSheet.swift), [Packages/StrandDesign/Sources/StrandDesign/TrendChart.swift](Packages/StrandDesign/Sources/StrandDesign/TrendChart.swift))

- **La app estrena nombre e icono: ahora se llama «Cénit» / The app has a new name and icon: it's now called "Cénit".**
  **ES** — NOOP ahora se llama **Cénit** —el punto más alto del recorrido del sol, el cénit del dial de 24 horas, en guiño al icono—. Es un cambio puramente de imagen: el nombre bajo el icono (app y widget), un nuevo icono «dial diurno» (anillo de 24 h con el arco del día en ámbar, la muesca del cénit arriba y el punto verde del «ahora») con sus tres aparencias de iOS 18 —claro, oscuro y tintado—, y todos los textos de la app pasan a «Cénit», en español, inglés y alemán. Tus datos, tu vínculo con la banda y tus respaldos quedan intactos: no hay que reinstalar ni volver a vincular nada, y los respaldos anteriores «NOOP-backup» se siguen restaurando igual.
  **EN** — NOOP is now called **Cénit** — the sun's highest point, the zenith of the 24-hour dial, echoing the icon. It's a pure rebrand: the name under the icon (app and widget), a new "daytime dial" icon (a 24-hour ring with the day's arc in amber, the cénit notch at the top and the green "now" dot) with its three iOS 18 appearances — light, dark and tinted — and every in-app text now reads "Cénit," in Spanish, English and German. Your data, your strap pairing and your backups are untouched: nothing to reinstall or re-pair, and older "NOOP-backup" files still restore exactly as before.
  ([project.yml](project.yml), [Cenit/System/ProjectInfo.swift](Cenit/System/ProjectInfo.swift), [Tools/gen-icon.swift](Tools/gen-icon.swift))

- **Hoy se lee más fácil: barra de estado en tinta, métricas más grandes y separadores más marcados / Today reads easier: dark status bar, larger metrics, and clearer separators.**
  **ES** — Pulido de legibilidad sobre el rediseño de **Hoy**: los íconos del sistema (hora, señal, batería) ahora se ven en **tinta oscura** sobre el papel claro, en vez de blancos y lavados. Las **«Métricas clave»** crecieron —etiquetas y números más grandes— para que el dato se lea de un vistazo, el título **«Métricas clave»** vuelve a tener contraste (antes quedaba casi invisible), y las **líneas divisorias** entre métricas y sobre «Verlo latido a latido» son un poco más gruesas y marcadas. Se quitó el rótulo «Hoy» sobre las métricas para un encabezado más limpio.
  **EN** — A legibility pass over the **Today** redesign: the system icons (clock, signal, battery) now show in **dark ink** on the light paper instead of washed-out white. **"Key Metrics"** grew — larger labels and numbers — so the data reads at a glance, the **"Key Metrics"** title has contrast again (it was nearly invisible before), and the **divider lines** between metrics and above "See it beat by beat" are a touch thicker and clearer. The "Today" overline above the metrics was removed for a cleaner header.
  ([Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift), [Packages/StrandDesign/Sources/StrandDesign/MetricRow.swift](Packages/StrandDesign/Sources/StrandDesign/MetricRow.swift))

- **La pantalla de Hoy se rediseñó: un número, un dial y la luz del día / The Today screen has been redesigned: one number, one dial, and daylight.**
  **ES** — Llegó el rediseño de **Hoy** (por ahora en iPhone): la pantalla es ahora **papel cálido que cambia de tono con la hora del día** —amanece, se ilumina y anochece contigo, con el modo claro «Instrumento diurno» y el cálculo de sol sin GPS de los pasos anteriores—. Manda **un solo número**: tu recuperación de 0 a 100, grande y en su propio color (verde / ámbar / rojo según la banda). A su lado, el **dial de 24 horas** marca la hora, tu **ventana de sueño** de anoche y tu **amanecer y atardecer**. Debajo, la **palabra del veredicto** lleva su propio color y una **«i»** que abre el porqué —puede no coincidir con el número, y eso está bien—. Tus **«Métricas clave»** (esfuerzo, sueño, HRV, frecuencia cardíaca, FC en reposo, oxígeno y pasos) bajan a una lista tranquila donde cada una muestra su **tendencia de 14 días** con una **banda de referencia** (tu rango típico) detrás de la línea. El color saturado vive **solo en el dato**; todo lo demás es tinta. No se perdió nada de información: solo se reacomodó para que respire.
  **EN** — The **Today** redesign has landed (on iPhone for now): the screen is now **warm paper that shifts tone with the time of day** — it dawns, brightens and darkens with you, using the "Instrumento diurno" light mode and the no-GPS sun math from the earlier steps. It leads with **one number**: your recovery from 0 to 100, large and in its own color (green / amber / red by band). Beside it, the **24-hour dial** marks the time, last night's **sleep window**, and your **sunrise and sunset**. Below, the **verdict word** carries its own color and an **"i"** that opens the why — it may not match the number, and that's fine. Your **"Key Metrics"** (strain, sleep, HRV, heart rate, resting HR, oxygen and steps) move into a calm list where each shows its **14-day trend** with a **reference band** (your typical range) behind the line. Saturated color lives **only in the data**; everything else is ink. No information was lost — it was just rearranged to breathe.
  ([Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift))

- **El encabezado de Hoy siempre muestra la fecha real, ya no se queda «atorado» en ayer / The Today header always shows the real date, no longer "stuck" on yesterday.**
  **ES** — La fecha bajo el saludo de la pantalla de Hoy mostraba el día del último dato registrado, no el del calendario. Antes de que existiera el registro de hoy, el encabezado se quedaba en ayer (p. ej. «lun, 15 de junio» cuando ya era 16), dando la impresión de que la app se había congelado. Ahora siempre muestra el día real de hoy, igual que el saludo.
  **EN** — The date under the greeting on the Today screen showed the day of the last recorded data, not the calendar day. Before today's row existed, the header stayed on yesterday (e.g. "Mon, Jun 15" when it was already the 16th), making the app look frozen. It now always shows the real current day, just like the greeting.
  ([Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift))

- **«En la banda» ya no muestra fechas imposibles / "On the band" no longer shows impossible dates.**
  **ES** — En el diagnóstico de Fuentes de datos, la línea «En la banda» —que muestra el rango de historial que dice tener tu strap— a veces enseñaba fechas basura: un solo día repetido (p. ej. «mar 15, 2025 → mar 15, 2025») o incluso fechas del futuro, porque la WHOOP 4.0 con el reloj inestable manda lecturas sin sentido. Ahora NOOP valida esa ventana antes de mostrarla: si no es plausible (fecha futura, o un rango colapsado a un solo punto), muestra «—» en vez de inventar un historial. Cuando la banda sí reporta un rango real, se muestra igual que antes.
  **EN** — In the Data Sources diagnostic, the "On the band" line — which shows the history range your strap claims to hold — sometimes displayed garbage dates: a single day repeated (e.g. "Mar 15, 2025 → Mar 15, 2025") or even future dates, because a WHOOP 4.0 with an unstable clock sends meaningless readings. NOOP now validates that window before showing it: if it isn't plausible (a future date, or a range collapsed to a single point), it shows "—" instead of inventing a history. When the band does report a real range, it's shown just as before.
  ([Cenit/BLE/BLEManager.swift](Cenit/BLE/BLEManager.swift))

- **Hoy reconoce de dónde viene tu base: Apple Health o tu banda / Today now recognizes where your baseline comes from: Apple Health or your strap.**
  **ES** — Antes de tu primer veredicto, la pantalla de Hoy ahora cuenta una historia coherente según de dónde salió tu base. Si importaste tu historial de **Apple Health**, ya no te pide «calibrar desde cero» ni muestra «0 de 4 noches»: te dice que **tu base ya está lista** y que solo falta que uses tu banda para el dato de hoy —el único que Apple Health no puede darte—. Si todavía no tienes historial, la tarjeta de calibración sigue contando tus noches 0→4, pero ahora aclara que son las noches que **tu propia base** necesita (no «tu veredicto») y te ofrece un atajo para conectar Apple Health y adelantar la base. Si no diste permiso a Apple Health, ningún mensaje te promete una base que no tienes. Es el complemento del cambio anterior en el veredicto (la línea «Se afina con tu banda · N de 14»).
  **EN** — Before your first verdict, the Today screen now tells a coherent story based on where your baseline came from. If you imported your **Apple Health** history, it no longer asks you to "calibrate from zero" or shows "0 of 4 nights": it tells you **your baseline is ready** and all that's missing is wearing your strap for today's reading — the one thing Apple Health can't give you. If you don't have history yet, the calibration card still counts your nights 0→4, but now it makes clear those are the nights **your own baseline** needs (not "your verdict") and offers a shortcut to connect Apple Health and give your baseline a head start. If you haven't granted Apple Health permission, no message promises a baseline you don't have. It's the companion to the earlier verdict change (the "Sharpening with your strap · N of 14" line).
  ([Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift))

- **El diagnóstico de sincronización ya distingue «la banda no está guardando (reloj)» de un error que reportar / The sync diagnostic now tells "the band isn't storing (clock)" apart from a bug to report.**
  **ES** — Antes, cuando una WHOOP 4.0 con el reloj perdido se conectaba, el diagnóstico de Fuentes de datos decía «Llegan datos pero no se decodifican — repórtalo». Era engañoso: no había nada que reportar; la banda simplemente no estaba guardando nada porque perdió la hora, así que solo manda mensajes internos (no biometría). Ahora ese caso —cuando no llega ni un registro biométrico y la banda no muestra historial guardado— se lee como «La banda no está guardando (reloj). Pásala por la app de WHOOP para reanudar», que es la acción correcta. El caso real en que sí llegan biométricos pero no se pueden decodificar conserva su mensaje de «repórtalo».
  **EN** — Before, when a WHOOP 4.0 with a lost clock connected, the Data Sources diagnostic said "Data arrives but doesn't decode — please report." That was misleading: there was nothing to report; the band simply wasn't storing anything because it lost the time, so it only sends internal log messages (no biometrics). Now that case — when not a single biometric record arrives and the band shows no stored history — reads "The band isn't storing data (clock). Run it through the WHOOP app to resume," which is the right action. The genuine case where biometric data does arrive but can't be decoded keeps its "report it" message.
  ([Cenit/BLE/LiveState.swift](Cenit/BLE/LiveState.swift))

- **Tu tendencia de variabilidad cardíaca ya no deja huecos los días que el strap no completó la noche / Your heart-rate-variability trend no longer leaves gaps on days the strap didn't finish the night.**
  **ES** — Si un día llevaste el strap pero NOOP no alcanzó a calcular tu variabilidad cardíaca (HRV) de esa noche —pasa en días de conexión parcial—, la mini-gráfica de 14 días y la tendencia de HRV en Hoy se quedaban con un hueco aunque Apple Salud sí tuviera el dato. Ahora rellenan ese día con el valor de Apple Salud, así la línea queda continua. Cuando el strap **sí** calculó tu HRV, ese valor manda y Apple no lo pisa. Esto es solo para lo que ves en la gráfica: tu recuperación y la calibración de tu línea base siguen contando únicamente las noches reales del strap, sin cambios.
  **EN** — If you wore the strap on a day but NOOP couldn't compute that night's heart-rate variability (HRV) — which happens on partial-connection days — the 14-day mini-chart and the HRV trend on Today were left with a gap even when Apple Health did have the value. They now fill that day from Apple Health, so the line stays continuous. When the strap **did** compute your HRV, that value wins and Apple never overrides it. This only affects what you see in the chart: your recovery and your baseline calibration still count strap-only nights, unchanged.
  ([Cenit/Data/Repository.swift](Cenit/Data/Repository.swift), [Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift))

- **NOOP ya puede calcular tu «Vitalidad» y tu «edad corporal» a partir de tus señales de bienestar / NOOP can now compute your "Vitality" and "Body Age" from your wellness signals.**
  **ES** — Nueva pieza de fondo: NOOP ya sabe calcular una «Vitalidad» (un puntaje de bienestar de 0 a 100) y una «edad corporal» (en años) combinando tu pulso nocturno en reposo, tu fitness (VO₂max), tu sueño, la regularidad de tu sueño, tu variabilidad cardíaca y tus pasos. Cada señal se traduce a su riesgo publicado de mortalidad por todas las causas (UK Biobank, FRIEND, Paluch 2022, Windred 2024, entre otros) y se combinan en una sola cifra. A diferencia de la «edad de fitness» —que mira solo lo cardiorrespiratorio—, la edad corporal es una mirada de **cuerpo entero** que suma sueño, regularidad, HRV y pasos. Tras una revisión experta del modelo le aplicamos seis correcciones para que sea honesto con los datos reales del strap: lo anclamos a tu pulso **nocturno**, separamos el riesgo de dormir poco del de dormir de más, ajustamos el solapamiento entre señales (para no castigar a quien tiene pocas), atenuamos la HRV (cuyos hazard ratios vienen de electrocardiograma clínico, no de la correa), corregimos la referencia de regularidad y volvemos el umbral de pasos sensible a la edad. Es, por diseño, una **comparación de bienestar, nunca una edad biológica ni un dato clínico**. Todavía no aparece en ninguna pantalla: es la base sobre la que se construirá esa vista después.
  **EN** — New groundwork: NOOP can now compute a "Vitality" (a 0–100 wellness score) and a "Body Age" (in years) by combining your nocturnal resting heart rate, your fitness (VO₂max), your sleep, your sleep regularity, your heart-rate variability and your steps. Each signal is mapped to its published all-cause-mortality risk (UK Biobank, FRIEND, Paluch 2022, Windred 2024, among others) and combined into a single number. Unlike "fitness age" — which looks only at the cardiorespiratory side — Body Age is a **whole-body** view that adds sleep, regularity, HRV and steps. After an expert review of the model we applied six corrections so it stays honest with real strap data: we anchor it to your **nocturnal** resting HR, separate the risk of sleeping too little from too much, adjust the overlap between signals (so users with few signals aren't penalized), attenuate HRV (whose hazard ratios come from clinical ECG, not the strap), fix the regularity reference, and make the steps threshold age-aware. It is by design a **wellness comparison, never a biological or clinical age**. It doesn't appear on any screen yet — it's the foundation that view will be built on later.
  ([Packages/StrandAnalytics/Sources/StrandAnalytics/VitalityEngine.swift](Packages/StrandAnalytics/Sources/StrandAnalytics/VitalityEngine.swift))

- **El nuevo «dial de 24 horas» de NOOP marca tu hora, tu sueño y tu sol / NOOP's new "24-hour dial" marks your time, sleep and sun.**
  **ES** — Pieza central del rediseño: NOOP ya tiene su «dial de 24 horas», un reloj con el **mediodía arriba y la medianoche abajo** donde un punto de luz marca la hora actual —entra con un barrido suave y late despacio—, sobre un aro que dibuja tu **ventana de sueño** y las marcas de **amanecer y atardecer** de tu zona. Cambia de tono con la hora del día (usa el modo claro «Instrumento diurno» del paso anterior) y respeta la preferencia de «reducir movimiento» del sistema: si está activa, se queda quieto. En las latitudes extremas, donde no hay amanecer ni atardecer, el aro queda limpio, sin cruce. Por diseño no lleva color: el tono saturado se reserva para el dato de salud que irá al centro. Todavía no aparece en ninguna pantalla —es el componente sobre el que se construirá el nuevo Hoy.
  **EN** — The centerpiece of the redesign: NOOP now has its "24-hour dial", a clock with **noon at the top and midnight at the bottom** where a point of light marks the current time — it sweeps in gently and pulses slowly — over a ring that draws your **sleep window** and your local **sunrise/sunset** marks. It shifts tone with the time of day (it uses the previous step's "Instrumento diurno" light mode) and respects the system's "reduce motion" preference: when that's on, it stays still. At extreme latitudes, where there's no sunrise or sunset, the ring stays clean, with no crossing. By design it carries no color — saturated hue is reserved for the health datum that will sit at its centre. It doesn't appear on any screen yet — it's the component the new Today will be built on.
  ([Packages/StrandDesign/Sources/StrandDesign/DiurnalDial.swift](Packages/StrandDesign/Sources/StrandDesign/DiurnalDial.swift))

- **NOOP ya puede estimar tu «edad de fitness» a partir de tu pulso y tu actividad / NOOP can now estimate your "fitness age" from your resting heart rate and activity.**
  **ES** — Nueva pieza de fondo: NOOP ya sabe calcular una «edad de fitness» —cómo se compara tu estado físico con el de una persona promedio de tu edad— a partir de tu pulso nocturno en reposo, tu actividad y tu perfil, usando un modelo científico publicado y revisado por pares (Nes/HUNT 2011). Tras una revisión experta del modelo, le aplicamos tres correcciones para que sea honesto con los datos reales del strap: lo anclamos al pulso **nocturno** (no al pulso sentado del estudio original, que dejaría a todos ~4 años más jóvenes), recalibramos la actividad a la escala de Esfuerzo de NOOP, y reservamos la banda de «±5 años» solo para la edad, no para el VO₂max. Es, por diseño, una **comparación de fitness, nunca una edad biológica ni un dato clínico**. Todavía no aparece en ninguna pantalla: es la base sobre la que se construirá esa vista después.
  **EN** — New groundwork: NOOP can now compute a "fitness age" — how your fitness compares to an average person your age — from your nocturnal resting heart rate, your activity and your profile, using a published, peer-reviewed model (Nes/HUNT 2011). After an expert review of the model, we applied three corrections so it stays honest with real strap data: we anchor it to **nocturnal** resting HR (not the original study's seated pulse, which would read everyone ~4 years younger), recalibrate activity to NOOP's Effort scale, and reserve the "±5 years" band for the age only, not the VO₂max. It is by design a **fitness comparison, never a biological or clinical age**. It doesn't appear on any screen yet — it's the foundation that view will be built on later.
  ([Packages/StrandAnalytics/Sources/StrandAnalytics/FitnessAgeEngine.swift](Packages/StrandAnalytics/Sources/StrandAnalytics/FitnessAgeEngine.swift))

- **Tu frecuencia cardíaca de hoy vive ahora en Métricas clave / Today's heart rate now lives in Key Metrics.**
  **ES** — En el iPhone, la gráfica de frecuencia cardíaca de 24 h dejó de ser una sección suelta al fondo de Hoy: ahora es un renglón más de «Métricas clave», justo encima de «FC en reposo». Muestra tu promedio del día y, al tocarlo, abre la curva de las últimas 24 horas —un poco más grande— con tus valores mínimo, promedio y máximo. Si todavía no hay lecturas del día, el renglón muestra «—» y el detalle avisa que aún no hay datos de hoy. Además, la tarjeta de «Fuentes» se movió de Hoy al final de la pantalla «Fuentes de datos». Así, Hoy queda como una sola pantalla: tu veredicto del día y tus métricas clave, sin scroll de más.
  **EN** — On iPhone, the 24h heart-rate chart is no longer a loose section at the bottom of Today: it's now a row in "Key Metrics", right above "Resting HR". It shows your average for the day and, when tapped, opens the last-24-hours curve — a little larger — with your min, average and max. If there are no readings yet today, the row shows "—" and the detail says so. The "Sources" card also moved from Today to the bottom of the "Data Sources" screen. Today now reads as a single screen: your day's verdict and your key metrics, with no extra scrolling.
  ([Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift), [Cenit/Screens/MetricInfoSheet.swift](Cenit/Screens/MetricInfoSheet.swift), [Cenit/Screens/SourcesSummaryCard.swift](Cenit/Screens/SourcesSummaryCard.swift), [Cenit/Screens/DataSourcesView.swift](Cenit/Screens/DataSourcesView.swift))

- **El nuevo modo claro de NOOP cambia de tono con la hora del día / NOOP's new light mode shifts its tone with the time of day.**
  **ES** — La siguiente etapa del rediseño (el lenguaje «Instrumento diurno», un modo claro sobre papel cálido) ahora respira con tu reloj: amanecer durazno, día neutro luminoso, atardecer ámbar y noche en pergamino atenuado. El cambio es continuo —se interpola minuto a minuto en un espacio de color perceptual, sin saltos bruscos— y se calcula por completo en tu dispositivo con la hora local (y, si está disponible, tu amanecer/atardecer del paso anterior). La noche se apaga y se entibia, pero **no** se vuelve modo oscuro: así el texto se mantiene legible —cumpliendo el estándar de accesibilidad AA— a cualquier hora. Es la pieza que tiñe todo el rediseño; todavía no cambia ninguna pantalla (las pantallas la adoptan en los siguientes pasos).
  **EN** — The next stage of the redesign (the «Instrumento diurno» language, a light mode on warm paper) now breathes with your clock: peach dawn, luminous neutral day, amber dusk, and a dimmed-parchment night. The shift is continuous — interpolated minute by minute in a perceptual color space, with no hard jumps — and computed entirely on your device from the local time (and, when available, your sunrise/sunset from the previous step). Night dims and warms but does **not** flip to dark mode, so text stays legible — clearing the AA accessibility standard — at any hour. It's the piece that tints the whole redesign; it doesn't change any screen yet (screens adopt it in the next steps).
  ([Packages/StrandDesign/Sources/StrandDesign/InstrumentoThemeEngine.swift](Packages/StrandDesign/Sources/StrandDesign/InstrumentoThemeEngine.swift))

- **NOOP ya puede estimar qué tanto se asocia cada deporte con tu recuperación (de momento, por dentro) / NOOP can now estimate how each sport is associated with your recovery (under the hood for now).**
  **ES** — Como base de un próximo insight, NOOP ya sabe calcular —por deporte— qué tanto tiende a bajar tu recuperación (Charge) la mañana siguiente a una sesión, comparado con tus días de descanso, y cuántos días suele tardar en volver. Es estadística descriptiva sobre tu propio historial —una asociación, no una relación de causa— calculada por completo en tu dispositivo. Por ahora vive solo «por dentro»: todavía no aparece en ninguna pantalla; eso llega después. Pasó por una revisión a fondo del método para no reportar ruido como si fuera señal: usa la mediana, exige al menos 6 sesiones y no anuncia efectos por debajo del margen de error de la medición.
  **EN** — As the groundwork for an upcoming insight, NOOP can now work out — per sport — how much your recovery (Charge) tends to dip the morning after a session versus your rest days, and how many days it usually takes to bounce back. It's descriptive statistics over your own history — an association, not cause — computed entirely on your device. For now it lives only under the hood: it doesn't appear on any screen yet; that comes later. It went through a careful review of the method so it doesn't report noise as signal: it uses the median, needs at least 6 sessions, and won't flag effects below the measurement's margin of error.
  ([Packages/StrandAnalytics/Sources/StrandAnalytics/ActivityCostEngine.swift](Packages/StrandAnalytics/Sources/StrandAnalytics/ActivityCostEngine.swift))

- **NOOP ya calcula tu amanecer y atardecer sin pedir tu ubicación / NOOP now works out your sunrise and sunset without asking for your location.**
  **ES** — Como base del rediseño que viene (el «dial de 24 horas»), NOOP ya sabe a qué hora amanece y atardece donde estás —aproximado, dentro de unos 15–30 min— calculado por completo en tu dispositivo, sin pedir permiso de ubicación y sin GPS: deduce tu región a partir de la zona horaria del teléfono. En las latitudes muy altas (sol de medianoche o noche polar) lo reporta como «sin amanecer/atardecer» en lugar de inventar una hora. Es la pieza sobre la que se dibujará el nuevo dial diurno; todavía no cambia ninguna pantalla.
  **EN** — As the foundation for the upcoming redesign (the "24-hour dial"), NOOP can now tell when the sun rises and sets where you are — approximately, within about 15–30 min — computed entirely on your device, with no location permission and no GPS: it infers your region from the phone's time zone. At very high latitudes (midnight sun or polar night) it reports "no sunrise/sunset" instead of inventing a time. It's the piece the new daytime dial will draw on; it doesn't change any screen yet.
  ([Packages/StrandAnalytics/Sources/StrandAnalytics/SolarClock.swift](Packages/StrandAnalytics/Sources/StrandAnalytics/SolarClock.swift))

- **Los textos más tenues (etiquetas y pies) se leen mejor / The faintest text (labels and captions) is easier to read.**
  **ES** — Las etiquetas en mayúsculas y los pies de gráfica en gris tenue de toda la app subieron un punto de contraste para cumplir el estándar de accesibilidad AA sobre las tarjetas, donde antes se quedaban apenas por debajo. Es un ajuste sutil, pero hace esos textos más legibles —sobre todo con poca luz o para quien batalla con el texto de bajo contraste.
  **EN** — The uppercase labels and chart captions in faint gray across the app were nudged up in contrast to meet the AA accessibility standard on cards, where they previously fell just short. It's a subtle change, but it makes that text more legible — especially in low light or for anyone who struggles with low-contrast text.
  ([Packages/StrandDesign/Sources/StrandDesign/Palette.swift](Packages/StrandDesign/Sources/StrandDesign/Palette.swift))

- **Tu registro del strap ya oculta tus identificadores al compartirlo / Your shared strap log now hides your identifiers.**
  **ES** — Cuando compartes tu registro del strap para ayudar a mapear el protocolo, NOOP ahora borra automáticamente tus datos personales antes de que salgan: la dirección MAC del Bluetooth queda enmascarada (solo su primer y último byte), el número de serie del WHOOP —que va en el nombre del dispositivo y está atado a tu cuenta— se elimina, y el identificador único de tu instalación se reemplaza por «<device>». Se conservan a propósito los UUID de servicio públicos (idénticos en todo strap) para que el registro siga sirviendo para diagnóstico.
  **EN** — When you share your strap log to help map the protocol, NOOP now automatically scrubs your personal data before it leaves: the Bluetooth MAC address is masked (first and last byte only), the WHOOP serial number — carried in the device name and tied to your account — is removed, and your install's unique identifier is replaced with "<device>". The public service UUIDs (identical on every strap) are deliberately kept so the log stays useful for diagnostics.
  ([Cenit/BLE/LiveState.swift](Cenit/BLE/LiveState.swift))

- **Tus fuentes de datos en Hoy ahora viven en una tarjeta ordenada / Your data sources in Today now live in a tidy card.**
  **ES** — La nota de fuentes al pie de Hoy se rediseñó como una tarjeta «FUENTES»: cada fuente en su renglón con un ícono propio (rayo+corazón para WHOOP, corazón para Apple Health) a la izquierda y sus conteos alineados a la derecha, y el estado de sincronización abajo, separado por una línea fina y con un puntito de color (ámbar si algo falló). Antes los dos badges de color competían entre sí y el texto colgaba sin orden. Mismo contenido, ahora ordenado y fácil de leer de un vistazo.
  **EN** — The data-sources note at the bottom of Today was redesigned as a "Sources" card: each source on its own row with its own icon (bolt+heart for WHOOP, heart for Apple Health) on the left and its counts aligned right, with the sync status below, set off by a thin divider and a small colored dot (amber if something failed). Before, the two colored badges competed and the text hung without order. Same content, now tidy and easy to read at a glance.
  ([Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift), [Packages/StrandDesign/Sources/StrandDesign/Components.swift](Packages/StrandDesign/Sources/StrandDesign/Components.swift))

- **Toca cualquier métrica clave para ver su tendencia de los últimos 14 días / Tap any key metric to see its 14-day trend.**
  **ES** — Al tocar Recuperación, HRV, FC en Reposo, Sueño, Oxígeno en Sangre o Pasos en Hoy, el sheet ahora muestra primero una gráfica de línea de los últimos 14 días — antes de las bandas de referencia y la explicación del método. La tendencia se arma con tu historial real combinado (tu banda cuando la tiene, Apple Health cuando no), igual que los mini-gráficos de los tiles, así que se llena aunque no hayas importado un CSV de WHOOP. El color y la escala son propios de cada métrica (gradiente indigo→menta para Recuperación y HRV, rosa para FC en Reposo, etc.), y el sheet se abre con la altura exacta que necesita para que la gráfica no quede cortada. Esfuerzo no la lleva: ya tiene su propia gráfica de «cómo se acumuló hoy».
  **EN** — Tapping Recovery, HRV, Resting HR, Sleep, Blood Oxygen or Steps in Today now shows a 14-day line chart at the top of the info sheet — before the reference bands and method disclosure. The trend is built from your real merged history (your strap when it has the day, Apple Health when it doesn't), the same source the tile sparklines use, so it fills in even without a WHOOP CSV import. Each metric uses its own color and scale (indigo→mint gradient for Recovery and HRV, rose for Resting HR, etc.), and the sheet opens just tall enough so the chart is never cut off. Strain doesn't get one: it already has its own "how today added up" curve.
  ([Cenit/Screens/MetricInfoSheet.swift](Cenit/Screens/MetricInfoSheet.swift), [Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift))

- **Toca y arrastra cualquier gráfica para ver el valor exacto de ese día / Touch and drag any chart to see the exact value for that day.**
  **ES** — Ahora puedes tocar cualquier `TrendChart` en la app (la gráfica de 14 días de HRV, Recuperación, FC en Reposo, Sueño, Oxígeno, Pasos, y la curva de acumulación del Esfuerzo de hoy) y arrastrar el dedo sobre ella: aparece un crosshair vertical, un punto resaltado sobre la línea y un tooltip con el valor exacto + la fecha. Mientras el dedo se mueve, el tooltip lo sigue en tiempo real. Al soltar, desaparece. Los macOS ya podían hacer esto con el cursor; ahora también funciona táctilmente en el iPhone.
  **EN** — You can now touch any `TrendChart` in the app (the 14-day trend charts for HRV, Recovery, Resting HR, Sleep, Blood Oxygen, Steps, and today's Strain accumulation curve) and drag your finger across it: a vertical crosshair, a highlighted dot on the line and a tooltip with the exact value + date appear and follow your finger in real time. Lift your finger and they fade away. macOS already had this with pointer hover; now it works on iPhone touch too.
  ([Packages/StrandDesign/Sources/StrandDesign/TrendChart.swift](Packages/StrandDesign/Sources/StrandDesign/TrendChart.swift))

- **La pantalla de Hoy queda más compacta — menos aire muerto vertical / The Today screen is more compact — less vertical dead space.**
  **ES** — Hoy se sentía holgada: demasiado espacio en blanco entre secciones y, sobre todo, mucho hueco arriba y abajo de la fila «Míralo latido a latido» (justo debajo de «Tu base viene de Apple Health»). Compactamos la pantalla: las secciones se acercan, la fila de latido queda mucho más ajustada, se recorta el aire bajo la tarjeta de veredicto, y toda la tarjeta de veredicto sube un poco hacia arriba. Mismo contenido, solo más junto. No cambia ninguna otra pantalla.
  **EN** — Today felt airy: too much whitespace between sections and, especially, a lot of empty space above and below the "See it beat by beat" row (right under "Your baseline comes from Apple Health"). We compacted the screen: sections sit closer, the heartbeat row is much tighter, the space below the verdict card is trimmed, and the whole verdict card sits a bit higher. Same content, just closer together. No other screen changes.

- **Fuentes de datos en Hoy se ven ordenadas en dos columnas / Data sources in Today are now laid out in a clean two-column grid.**
  **ES** — WHOOP y Apple Health ahora aparecen lado a lado, cada uno con su badge arriba y sus conteos debajo. Antes, cuando los dos estaban activos, el texto se partía de forma rara con el separador «·» colgando al final de la primera línea.
  **EN** — WHOOP and Apple Health now sit side by side, each with its badge on top and counts below. Previously, when both were active, the text broke awkwardly with the separator «·» dangling at the end of the first line.
  ([Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift))

- **Tu tarjeta de hoy ya no confunde una recuperación alta con un veredicto exigente / Your Today card no longer makes a high recovery look like it's fighting the verdict.**
  **ES** — Si amaneces muy recuperado (digamos 92) pero el veredicto del día sale «Exigido», antes parecía una contradicción — y el 92 hasta se pintaba del color del veredicto (ámbar). Ahora la tarjeta muestra dos cosas distintas, lado a lado y cada una en su color: tu **Veredicto** (¿te exiges hoy?) y tu **Recuperación** (¿qué tan recuperado amaneciste?, 92/100, en verde). Una frase abajo las reconcilia: «Amaneciste muy recuperado. Lo que pide cuidado: hoy es tu carga, no tu cuerpo». Y un enlace «¿Por qué exigido?» abre una pantalla que explica qué señal pesó (HRV, carga, FC en reposo…) y qué significa cada color (menta = Listo, verde = Equilibrado, ámbar = Exigido, rosa = Desgastado), marcando en cuál estás hoy — información que en el iPhone antes no aparecía. «Listo» ahora se ve en menta brillante, distinto del verde de «Equilibrado». No cambia cómo se calcula tu recuperación ni tu veredicto.
  **EN** — When you wake up well recovered (say 92) but the day's verdict reads "Strained", it used to look like a contradiction — and the 92 was even painted in the verdict's color (amber). Now the card shows two separate things, side by side and each in its own color: your **Verdict** (should you push today?) and your **Recovery** (how recovered did you wake up?, 92/100, in green). A line below reconciles them: "You woke up well recovered. What needs care today is your training load, not your body." And a "Why strained?" link opens a screen explaining which signal weighed in (HRV, load, resting HR…) and what each color means (mint = Primed, green = Balanced, amber = Strained, rose = Run down), marking where you land today — information that wasn't on iPhone before. "Primed" now shows in a bright mint, distinct from "Balanced" green. How your recovery and verdict are computed is unchanged.
  ([Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift), [Cenit/Screens/WhyVerdictSheet.swift](Cenit/Screens/WhyVerdictSheet.swift), [Packages/StrandAnalytics/Sources/StrandAnalytics/ReadinessEngine.swift](Packages/StrandAnalytics/Sources/StrandAnalytics/ReadinessEngine.swift), [Packages/StrandDesign/Sources/StrandDesign/Palette.swift](Packages/StrandDesign/Sources/StrandDesign/Palette.swift))

- **Toca tu HRV para ver de dónde sale ese número / Tap your HRV to see where that number comes from.**
  **ES** — Igual que con la recuperación, ahora puedes tocar «HRV» en la fila de resumen de Hoy (y en Métricas clave) para entenderlo en lenguaje llano: qué es la variabilidad entre latidos, por qué importa tu propia tendencia y no un umbral universal, y —a un toque más— cómo se calcula (tomamos los intervalos entre latidos de tu noche, descartamos los fuera de 300–2000 ms y los latidos raros, y si quedan al menos 20 limpios sacamos el RMSSD; Task Force 1996, regla de Malik). Si no hubo HRV anoche, te dice por qué. Todo en tu dispositivo.
  **EN** — Just like recovery, you can now tap "HRV" in the Today summary row (and in Key Metrics) to understand it in plain language: what beat-to-beat variability is, why your own trend matters more than any universal threshold, and — one tap deeper — how it's computed (we take the intervals between your heartbeats overnight, drop the ones outside 300–2000 ms and the odd beats, and if at least 20 clean ones remain we compute RMSSD; Task Force 1996, Malik's rule). If there was no HRV last night, it tells you why. All on your device.
  ([Cenit/Screens/MetricInfoSheet.swift](Cenit/Screens/MetricInfoSheet.swift), [Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift))

- **Mira cuántos días vienen de tu banda y cuántos de Apple Health / See how many days come from your strap vs. Apple Health.**
  **ES** — En Fuentes de datos → card de Apple Health aparece una nueva sección «Cobertura de datos»: un grid de 30 cuadros, uno por día, que muestra de dónde vino cada dato — verde si lo midió la banda, cyan si solo vino de Apple Health, gris si no hay dato. Una línea de resumen arriba del grid y una leyenda abajo hacen la lectura inmediata. Sin taps ni ventanas nuevas; sólo una vista honesta de cómo la banda va reemplazando a Apple Health día a día.
  **EN** — In Data Sources → Apple Health card, a new "Data coverage" section shows a 30-cell grid — one cell per day — color-coded by source: green if the strap measured it, cyan if it came from Apple Health only, gray if there's no data. A summary line above the grid and a legend below make it instantly readable. No taps, no new screens; just an honest view of how the strap is taking over from Apple Health day by day.
  ([Cenit/Screens/DataSourcesView.swift](Cenit/Screens/DataSourcesView.swift))

- **Toca tu número de recuperación para ver de dónde sale / Tap your recovery number to see where it comes from.**
  **ES** — Al tocar «Recuperación» en la fila de resumen de Hoy se abre una explicación en lenguaje llano de cómo se arma tu número del 0 al 100: cuánto pesa cada señal de tu noche (HRV 60 %, FC en reposo 20 %, sueño 15 %, temperatura de piel 10 %, respiración 5 %) y, a un toque más, el método detrás —cada señal comparada con tu propio promedio, RMSSD, Task Force 1996—. Si tu base aún se está calibrando, te dice por qué todavía no hay número en vez de inventarlo. Todo en tu dispositivo; es una estimación, no un diagnóstico.
  **EN** — Tapping "Recovery" in the Today summary row now opens a plain-language explanation of how your 0–100 number is built: how much each signal from your night counts (HRV 60%, resting HR 20%, sleep 15%, skin temp 10%, respiration 5%) and, one tap deeper, the method behind it — each signal compared with your own average, RMSSD, Task Force 1996. While your baseline is still calibrating, it tells you why there's no number yet instead of making one up. All on your device; it's an estimate, not a diagnosis.
  ([Cenit/Screens/MetricInfoSheet.swift](Cenit/Screens/MetricInfoSheet.swift), [Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift))

- **Mira cómo se acumuló tu esfuerzo a lo largo del día / See how your strain built up through the day.**
  **ES** — Al tocar «Esfuerzo del día» en Hoy, debajo de la tabla de zonas aparece una gráfica nueva, «Cómo se acumuló hoy»: la curva de tu esfuerzo subiendo desde la medianoche hasta el número que ves arriba, para que veas de dónde salió tu puntaje y a qué horas te exigiste. El eje se ajusta solo a tu día, así que incluso un día tranquilo se lee claro. Si aún no hay suficiente actividad, en su lugar aparece un aviso breve. Se calcula al vuelo con los datos de hoy, en tu dispositivo.
  **EN** — Tapping "Day Strain" on Today now shows a new chart below the zones table, "How today added up": your strain rising from midnight to the number shown above, so you can see where your score came from and when you pushed hardest. The axis fits your own day, so even a quiet day reads clearly. When there isn't enough activity yet, a short note appears instead. Computed on the fly from today's data, on your device.
  ([Cenit/Screens/MetricInfoSheet.swift](Cenit/Screens/MetricInfoSheet.swift), [Packages/StrandAnalytics/Sources/StrandAnalytics/StrainScorer.swift](Packages/StrandAnalytics/Sources/StrandAnalytics/StrainScorer.swift), [Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift))

- **Tu veredicto te dice de dónde viene tu base y cuánto le falta para afinarse / Your verdict now shows where your baseline comes from and how far it has to sharpen.**
  **ES** — Si importaste tu historial de Apple Health, NOOP puede darte el veredicto del día con una sola noche de banda — lo que antes confundía ("¿no eran varias noches?"). Ahora, al pie del veredicto, una barra discreta —«Se afina con tu banda · N de 14 noches»— muestra que tu cálculo sigue afinándose con cada noche que usas la banda, y cuando tu base se sembró con Apple Health, te lo dice. La barra se retira sola al llegar a tus 14 noches; una noche corta cede el lugar al aviso de baja confianza. No cambia cómo se calcula tu recuperación.
  **EN** — If you imported your Apple Health history, NOOP can give you the day's verdict after a single strap night — which used to feel confusing ("wasn't it supposed to take several nights?"). Now, at the foot of the verdict, a quiet bar —"Sharpening with your strap · N of 14 nights"— shows your read keeps sharpening with every strap night, and when Apple Health seeded your baseline it says so. The bar retires itself once you reach 14 nights; a short night yields the spot to the low-confidence note. Recovery scoring is unchanged.
- **NOOP escribe tu sueño de WHOOP en Apple Salud / NOOP writes your WHOOP sleep to Apple Health.**
  **ES** — Tras cada sincronización, las fases de sueño que la WHOOP mide toda la noche (light, deep, REM, wake) aparecen en la app de Salud como fuente "NOOP". La WHOOP mide las fases con PPG continua durante la noche, a diferencia del Apple Watch que hace muestreos puntuales. Los datos coexisten con los del Watch y el usuario elige cuál tiene prioridad en Salud → [métrica] → Fuentes. No se crean duplicados: NOOP borra sus propias entradas anteriores antes de escribir las nuevas.
  **EN** — After each sync, the sleep stages WHOOP measures throughout the night (light, deep, REM, wake) appear in the Health app under the "NOOP" source. WHOOP measures stages with continuous PPG all night, unlike Apple Watch which takes spot readings. The data coexists with Watch readings and the user can set priority in Health → [metric] → Data Sources. No duplicates are created: NOOP deletes its own prior entries before writing new ones.
  ([CenitApp/Health/HealthKitBridge.swift](CenitApp/Health/HealthKitBridge.swift))

- **La info de fuentes en "Hoy" ocupa menos espacio / Data source info on Today takes less space.**
  **ES** — La sección "Procedencia" al fondo de la pantalla Hoy era un card grande (con título de sección y tres renglones separados) que le daba peso de pantalla principal a información secundaria. Ahora aparece como dos líneas discretas en el fondo del scroll: una con los badges de fuente y conteos, otra con el estado del último sync de la banda.
  **EN** — The "Provenance" section at the bottom of Today was a full card (with section title and three separate rows) that gave primary-screen weight to secondary metadata. It now appears as two compact lines at the bottom of the scroll: one with source badges and counts, one with the strap's last sync status.
  ([Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift))

- **"Procedencia" muestra ahora el recuento correcto de días de la banda / "Provenance" now shows the correct strap day count.**
  **ES** — El renglón "Whoop" en la sección de Procedencia contaba todos los días del dashboard (incluyendo los de Apple Health), no solo los días donde la banda fue la fuente ganadora. Con 31 días de Apple Health y 1 de la banda, mostraba "32 días" en lugar de "1 día". Ahora el conteo es exacto: solo aparecen los días con datos reales del strap.
  **EN** — The "Whoop" row in the Provenance section was counting every day in the dashboard (including Apple Health days) instead of only the days where the strap won. With 31 Apple Health days and 1 strap day it showed "32 days" instead of "1 day". The count is now accurate: only days with real strap data are shown.
  ([Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift))

- **"Métricas clave" rellena con Apple Salud cuando la banda viene vacía / "Key Metrics" fills from Apple Health when the strap comes up empty.**
  **ES** — Si tu banda registraba el día pero sin HRV / sueño / FC en reposo / oxígeno (le pasa a la WHOOP 4.0 cuando no alcanza a decodificar), esos datos tapaban los que Apple Salud sí tenía y "Métricas clave" quedaba en "—". Ahora, cuando la banda no trae el valor de hoy o ayer, "Métricas clave" usa el de Apple Salud (marcado "Apple Health"). Si la banda sí lo tiene, ese gana. No cambia el cálculo de recuperación.
  **EN** — If your strap logged the day but without HRV / sleep / resting HR / blood oxygen (which happens to the WHOOP 4.0 when it can't decode them), that empty row hid the values Apple Health did have and "Key Metrics" showed "—". Now, when the strap lacks today's or yesterday's value, "Key Metrics" uses Apple Health's (badged "Apple Health"). If the strap has it, the strap wins. Recovery scoring is unchanged.
  ([Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift), [Cenit/Data/Repository.swift](Cenit/Data/Repository.swift))

- **La pantalla "Apple Health" ya muestra lo que sincronizas en vivo / The "Apple Health" page now shows what you sync live.**
  **ES** — Si conectabas Apple Salud (sin importar un archivo de exportación), la pantalla "Apple Health" (en Más), "Explorar" y "Comparar" salían vacías aunque los datos sí estaban en el teléfono. Era porque la sincronización en vivo no llenaba la tabla que esas pantallas leen. Ahora sí: tus pasos, FC en reposo, HRV, oxígeno, sueño y energía aparecen ahí —y las mini-gráficas de Apple en Hoy se dibujan— sin necesidad de importar nada.
  **EN** — If you connected Apple Health (without importing an export file), the "Apple Health" page (in More), "Explore" and "Compare" came up empty even though the data was on your phone — the live sync wasn't filling the table those screens read from. Now it does: your steps, resting HR, HRV, blood oxygen, sleep and energy show up there, and the Apple sparklines on Today draw, with nothing to import.
  ([CenitApp/Health/HealthKitBridge.swift](CenitApp/Health/HealthKitBridge.swift))

- **Sincronización discreta: el indicador de sincronización ya no interrumpe la pantalla / Quiet sync indicator: syncing no longer interrupts the screen.**
  **ES** — Mientras la app descarga el historial de la banda, ya no aparece un pill verde pulsante en la pantalla. En su lugar, la pequeña línea de estado en la esquina superior derecha (la misma que muestra "Sincronizado hace 2 min · banda 87%") cambia discretamente a "Sincronizando historial de la banda…" en el mismo tono gris apagado. Cuando termina, vuelve al estado normal sin ningún parpadeo.
  **EN** — While the app downloads strap history, the pulsing green pill no longer interrupts the screen. Instead, the small status line in the top-right corner (the one that shows "Synced 2 min ago · strap 87%") quietly reads "Syncing strap history…" in the same muted gray. When it finishes, it returns to normal with no flash.
  ([Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift), [Cenit/Screens/IntelligenceView.swift](Cenit/Screens/IntelligenceView.swift), [Cenit/Screens/SleepView.swift](Cenit/Screens/SleepView.swift))

- **Apple Salud se queda conectado entre aperturas / Apple Health stays connected between launches.**
  **ES** — Antes, al cerrar y reabrir la app tenías que volver a conectar Apple Salud cada vez, y
  "Métricas clave" en Hoy se quedaba solo con "Esfuerzo del día". Ahora la conexión se recuerda: al
  reabrir, la sincronización corre sola y tus métricas de Apple Salud (HRV, sueño, FC en reposo,
  oxígeno, pasos) vuelven a aparecer sin reconectar. Y si todavía no has conectado Apple Salud,
  "Métricas clave" muestra un acceso discreto "Conectar Apple Salud" que te lleva a Fuentes de datos.
  **EN** — Closing and reopening the app used to make you reconnect Apple Health every time, leaving
  Today's "Key Metrics" with just "Day Strain." The connection is now remembered: on reopen the sync
  runs on its own and your Apple Health metrics (HRV, sleep, resting HR, blood oxygen, steps) come
  back without reconnecting. And if you haven't connected Apple Health yet, "Key Metrics" shows a
  discreet "Connect Apple Health" shortcut that takes you to Data Sources.
  ([CenitApp/Health/HealthKitBridge.swift](CenitApp/Health/HealthKitBridge.swift), [Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift))

- **Tu pulso en vivo y el monitor latido a latido, en cada pantalla / Live pulse and the beat-to-beat monitor, on every screen.**
  **ES** — La fila "Míralo latido a latido" (con tu `• NN bpm` en vivo) ahora aparece al pie del
  veredicto del día y de la pantalla "Aún sin lectura de hoy", no solo durante la calibración. Tócala
  para ver tu corazón latido a latido — antes no había forma de abrir ese monitor desde el veredicto.
  Y el encabezado quedó definitivamente limpio (solo fecha y sincronización) en todas las pantallas.
  Si la banda no transmite, la fila dice "Sin lectura".
  **EN** — The "See it beat by beat" row (with your live `• NN bpm`) now sits at the foot of the day's
  verdict and of the "No reading for today yet" screen, not just during calibration. Tap it to watch
  your heart beat to beat — there was no way to open that monitor from the verdict before. And the
  header is finally clean (just date and sync) on every screen. When the strap isn't streaming, the
  row reads "No reading".
  ([Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift))

- **Tu pulso en vivo se mudó a la tarjeta de tu primera noche / Live heart rate moved into the first-night card.**
  **ES** — Durante la calibración (la pantalla de las 4 noches), tu ritmo cardiaco en vivo ya no va
  arriba en el encabezado: ahora aparece como `• NN bpm` en la fila "Míralo latido a latido" de la
  tarjeta, justo donde tocas para verlo latido a latido. El encabezado queda solo con la fecha y la
  sincronización. Si la banda no está transmitiendo, la fila dice "Sin lectura".
  **EN** — During calibration (the four-night screen), your live heart rate no longer sits up in the
  header: it now shows as `• NN bpm` in the card's "See it beat by beat" row, right where you tap to
  watch it live. The header is just date and sync. When the strap isn't streaming, the row reads
  "No reading".
  ([Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift))

- **La fila de Recuperación / HRV / Sueño ahora va centrada / Recovery · HRV · Sleep row is now centered.**
  **ES** — La franja de resumen bajo el veredicto (Recuperación, HRV, Sueño) estaba pegada a la
  izquierda con un hueco a la derecha. Ahora sus tres columnas van centradas y balanceadas, con los
  separadores a la misma distancia. Solo cambia la alineación; los números son los mismos.
  **EN** — The summary strip under the verdict (Recovery, HRV, Sleep) hugged the left with a gap on
  the right. Its three columns are now centered and balanced, with evenly spaced dividers. Only the
  alignment changed; the numbers are the same.
  ([Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift))

- **WHOOP 4.0 clock & history diagnostics in the strap log.** When syncing a 4.0, the strap log now
  spells out three things in plain language: the band's own clock as a readable date (or that it never
  answered), the retained-history window it reports (`oldest → newest`, or that it holds nothing), and
  a per-offload breakdown of what actually arrived (biometric records vs. firmware console logs vs.
  other). This makes it possible to tell apart "the band's clock is wrong so it never saved history"
  from "the band has nothing new" — without guessing. Observability only; no new strap commands.
  ([Cenit/BLE/BLEManager.swift](Cenit/BLE/BLEManager.swift), [Cenit/Collect/Backfiller.swift](Cenit/Collect/Backfiller.swift))

- **The Today header no longer pulses — calmer, with more room for what matters.** The animated ECG
  waveform that rode the top of the Today screen is gone. The header now reads as a quiet date + sync
  line with your live heart rate still pinned to the right — just without the decorative pulse, which
  ate the most valuable strip of the screen without telling you anything. (First of a few small steps
  tidying the Today header.) ([Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift))

- **Strap sync diagnostic in Data Sources — honest proof your data is getting through.** The WHOOP
  strap row now expands into a read-only diagnostic that answers "did the band capture data, and is
  NOOP receiving, decoding and storing it?" It shows the band's own retained-history window
  (`oldest → newest`, from the strap's last data-range report — proof the sensor captured and still
  holds it), a **Sync now** button that forces a single safe history offload and shows live progress,
  a per-sensor receipt of what landed this sync (heart rate, R-R, blood oxygen, temperature,
  respiration, movement), and one honest verdict: *Receiving and storing everything* · *The band has
  nothing new* · *Data arrives but doesn't decode — please report*. It only informs — the sole action
  is Sync now (never a reboot/wipe). Localized in English and Spanish. ([Cenit/Screens/DataSourcesView.swift](Cenit/Screens/DataSourcesView.swift))

- **Debug screenshot fixtures for Today's readiness states (developers only).** A new DEBUG-only `ScreenshotFixtures` seeds ~40 days of deterministic synthetic history — reverse-engineered against `ReadinessEngine` + `Baselines` — so TodayView can be captured in a specific verdict on demand: `-noop.fixture primed` (signals aligned, load supported) or `-noop.fixture strained` (one signal flagging). The seed publishes a matching dashboard plus synthetic workouts and a 24h heart-rate trace, and `AppModel.init` skips the production refresh loop while a fixture is active so it isn't overwritten. The `NOOPScreenshotTests` UI test gained one isolated method per state (`test_captureTodayEmpty/Primed/Strained`) that captures a top→bottom scroll sequence. All `#if DEBUG`-gated; no effect on release builds. ([Cenit/App/ScreenshotFixtures.swift](Cenit/App/ScreenshotFixtures.swift))

- **Fix: trend charts no longer tint the hour labels or clip the last one.** On a tight value domain
  (e.g. the heart-rate chart on Today, 64–145 bpm) the area fill anchored to its implicit zero
  baseline — which sits *below* the domain — so it filled all the way to the plot's bottom edge,
  straight behind the X-axis labels and tinting "2:25 p.m. / 2:40 p.m. …" a faint red; the rightmost
  label was also cut off ("3:25 p..." instead of "3:25 p.m."). The fill is now pinned to the value
  domain's floor (`AreaMark` `yStart`), and the Y-scale reserves a clean band below it for the labels
  while the X-scale insets its trailing edge so the last label renders in full
  (`NoopMetrics.chartXLabelBand` / `chartXTrailingInset`). Pinning the floor also makes the fill
  *physically unable* to bleed below the axis onto the footer (reinforces FER-10). Applies everywhere
  `TrendChart` is used — Today (heart rate), Trends and Explore — since it's one shared component;
  `.monotone` interpolation and the hover/crosshair logic are untouched. Verified by rendering the
  card to PNG in a unit test (`ChartSnapshotTests`).
  ([Packages/StrandDesign/Sources/StrandDesign/TrendChart.swift](Packages/StrandDesign/Sources/StrandDesign/TrendChart.swift)) (FER-82)

- **Today is shorter on iPhone: the "Last Workouts" strip is gone.** Today should read at a glance,
  and your workouts already have their own Workouts tab — repeating them on the home screen only added
  scroll. Today now flows verdict → Key Metrics → Heart Rate → Data Sources. Nothing else changed:
  the Workouts tab still lists every session, the Apple Health workout count in Data Sources is
  unaffected, and macOS keeps its "Last Workouts" section. ([Cenit/Screens/TodayView.swift](Cenit/Screens/TodayView.swift))

- **Debug screenshot automation (developers only).** iOS debug builds now register a Darwin notification listener (`noop.nav.<screen>`) so every screen can be navigated programmatically — `xcrun simctl spawn booted notifyutil -p noop.nav.trends` — without triggering system permission dialogs. The "More" tab was refactored to use `NavigationLink(value:)` with a typed `MoreScreen` enum and a programmatic `NavigationPath`, enabling deep-link navigation into any sub-screen from the command line. A `noopdev://` URL scheme (backup transport) is also registered. All debug code is `#if DEBUG`-gated; it has no effect on release builds. ([CenitApp/App/ScreenshotNav.swift](CenitApp/App/ScreenshotNav.swift))

- **Fix: `MetricInfoSheet` now compiles on macOS 13.0.** `.presentationBackground(_:)` requires macOS 13.3 but the sheet was calling it unconditionally. Wrapped in a `PresentationBackgroundModifier` with an `@available(macOS 13.3, iOS 16.4, *)` guard.

- **The Heart Rate graph on Today now fills from a live-only session (iPhone).** If you wore the strap
  with NOOP connected but never imported a WHOOP export, today's Heart Rate chart stayed empty even
  though your live pulse showed at the top of the screen. The live heart rate streaming over the
  strap's realtime channel was shown but never saved, so the chart had nothing to draw. It's now
  recorded as it streams (deduplicated so a strap sending both channels isn't double-counted), and the
  chart appears on its own after a few minutes of wear — no import or app restart needed.
- **Apple Health workouts now appear in Today and Workouts (iPhone).** The live Apple Health sync asked
  for workout permission but never actually fetched them — only the manual XML export brought them in.
  The sync now queries HealthKit workouts in the same window as the rest of your health data, so
  "Last Workouts" on Today and the Workouts tab fill in automatically on every sync without needing
  to export anything. Activity names come through correctly (e.g. "Traditional Strength Training",
  "Running") and the progress bar shows "Workouts (12/13)" while they load.

- **The wait for your first verdict is alive now (iPhone, FER-61).** Before NOOP has banked enough
  nights to compute a verdict, Today shows a night-by-night progress card from night zero — four dots
  that fill in as each valid night lands (0 of 4 → 4 of 4), so you always see how many nights are left
  instead of a blank screen. Tap "See it beat by beat" to open a live monitor: your heart rate on a
  hospital-style ECG sweep, a "beats this session" counter that climbs in real time, and a
  beat-to-beat variability tachogram that draws itself as each beat arrives. It stays honest about
  what is live versus not — heart rate and variability stream beat to beat, while SpO₂, skin
  temperature, respiration and movement are marked "completes on sync" — and a footer confirms when
  everything is saved (or warns when you're streaming live HR without having finished the secure
  pairing the rest of the data needs). Fully localized (English + Spanish).
- **"Resting HR" help text no longer assumes the WHOOP strap (iPhone, FER-77).** Tapping Resting HR in
  Key Metrics described it as "your lowest heart rate during sleep" — true for the strap, but since
  Apple Health now fills the value when the strap hasn't (FER-62), that wording was wrong for the
  Apple-sourced reading (Apple computes resting heart rate its own way, across the day). The help text
  now describes the metric without assuming a source, and a footnote names both: measured overnight by
  the strap, or read from Apple Health's resting heart rate when the strap isn't worn. Copy-only; no
  calculation change.

- **Apple Health strength workouts read as words again, not one run-on label (iPhone, FER-76).** On
  Today, the "Last Workouts" tiles took the workout type straight from Apple Health, so a *Traditional
  Strength Training* session showed up as a single glued, all-caps word (`TRADITIONALSTRENGTHTRAINING`)
  that wrapped mid-word and overlapped the duration beneath it. The name is now split back into words
  ("Traditional Strength Training"), and every metric/workout tile caps its label at two lines so a
  long name can no longer collide with its value. Also clears the same run-on name in the Workouts
  list and the per-sport breakdown.
- **Your data backs itself up to iCloud Drive, so a reinstall can't lose it (iPhone, FER-74).** Your
  strap's history lives only inside NOOP — once the band hands a night over it deletes its own copy —
  so deleting or reinstalling the app used to lose it for good. Now you can pick a folder in your own
  iCloud Drive (a free Apple ID is enough — this isn't a paid developer-iCloud feature) and NOOP keeps
  a fresh copy of everything there, refreshed automatically after each sync (about once a day, while
  the app is open). If you ever open NOOP to an empty screen — a fresh install, a new phone — it
  offers to restore from that backup in one tap; you can also back up or restore any time from
  Settings. Apple Health and an imported WHOOP export re-fill on their own, so this protects the one
  thing that can't: the strap's own history. Honest limits: iCloud uploads when iOS decides (usually
  minutes), and after deleting the app you re-pick the folder once. Fully localized (English +
  Spanish).
- **The "14-day" header on Key Metrics now reads "14-day trend" (iPhone).** The header above the Key
  Metrics list paired "Today" with a bare "14-day", which read as if the values themselves spanned 14
  days rather than being today's reading (steps, for example, are today's total; blood oxygen is a
  daily average). It now says "14-day trend", so the period clearly labels the sparkline beside each
  row — the trend — not the number. This also brings iPhone in line with macOS, which already showed
  "14-day trend". Fully localized (English + Spanish + German).

- **Trends and Sleep fill in from Apple Health before the strap does (FER-62).** If you've connected
  Apple Health but the strap hasn't covered a day yet, Trends now plots your HRV and resting heart
  rate from Apple Health, and Sleep shows last night's stage breakdown from it — each tagged with an
  "Apple Health" badge so the source is clear. The strap always wins: any day or night the strap
  covers shows the strap's reading, and Apple Health only fills the gaps. Apple's sleep is shown as a
  proportional deep / light / REM bar (no minute-by-minute hypnogram — that's strap-only). Fully
  localized (English + Spanish + German).
- **"Key Metrics" on Today fills in from Apple Health too (FER-62 follow-up).** Until now only Steps
  read from Apple Health on the Today screen — HRV, resting heart rate, sleep and blood oxygen stayed
  blank whenever the strap hadn't scored the day, even though Apple Health had the data. They now show
  your Apple Health reading, each tagged "Apple Health" so it's never mistaken for a live strap value
  — the same treatment Trends and Sleep already got. To keep the "Today" label honest, a value only
  fills in if it's from today or yesterday; anything older reads "—" (the full history still shows in
  Trends). Day Strain stays strap-only — it's a computed score Apple doesn't provide. Also closed a
  gap where a stale import could show a months-old Steps count under Today; it's now bounded to recent
  days. No new copy — reuses the existing "Apple Health" tag, so it's localized everywhere already.
- **The live heart-rate ECG reads like a real monitor now (iPhone, FER-58).** When your strap is streaming, the brand ECG strip on Today no longer just scrolls one fixed wave faster or slower. A sweep head moves across the strip drawing each heartbeat the instant it reaches that beat — complexes spaced by your live BPM, so a faster heart packs them closer together. The trace now stays continuous like a hospital monitor: the head wipes last pass forward into this one behind a small erase gap instead of blanking to a flat line, so the beats no longer jump sideways between passes. And the beat breathes — subtle beat-to-beat variation in spacing and height plus a slow respiratory drift — so it reads like a living heart rather than one frame looping. With no strap connected it rests on a calm flatline.
- **Apple Health import is no longer a black box (FER-70).** Connecting or syncing Apple Health used
  to run silently — you couldn't tell whether it was working, how many days came in, or which metrics
  never arrived. The "Apple Health — Live Sync" card on Data Sources now shows live per-stage progress
  while it runs ("Importing HRV… · 4/12"), then a coverage summary ("12 May → 9 Jun · 28 d") and a
  per-metric checklist of exactly what landed (HRV ✓ 28 d · Sleep ✓ 25 d · SpO₂ —). It links straight
  to Settings to grant any missing permission, and the onboarding import step now shows a live record
  counter so a long export reads as progressing rather than frozen. NOOP also stops asking for the
  Body Temperature permission it never actually imported. Fully localized (English + Spanish).
- **Tap any metric to learn what it means (iPhone).** Every row in "Key Metrics" is now tappable. A bottom sheet opens showing what the metric measures, how it is calculated, and a colour-coded range table (e.g. Rest · Moderate · Hard · Extreme for strain) with your current value highlighted in its band. Covers Day Strain, Sleep, HRV, Resting HR, Blood Oxygen, and Steps.
- **No-data screen stays honest when the strap connects mid-onboarding.** Previously the Today screen would flip from the clean "No reading yet" hero to the older "Scores are building" state the moment a strap was seen, even before any recovery data arrived. Now a single adaptive hero covers both states: it shows "No reading yet / Scan for strap" until a strap is ever seen, then "Your scores are building" once one is — always without fabricated gauges or dashes.
- **Redesigned Today screen (iPhone).** The Today tab is now a tighter, verdict-first "instrument"
  read. It opens with an honesty line ("Synced 2 min ago · strap 87%" / "Last sync — never") and the
  brand ECG strip with your live heart rate, then a single committed verdict — "You're Primed",
  "Ease off today", or "No reading yet" on a fresh install — with a 0–100 readiness gauge that fills
  to today's score. After a short night the verdict honestly flags itself "confidence low" (and HRV
  carries a small "Low conf" tag) instead of pretending to be sure. Below, a borderless
  Recovery · HRV · Sleep synthesis and a dense Key Metrics list (label · sparkline · value) replace
  the old tile grid, and a true first-launch empty state shows skeletons + a "Scan for strap" action
  rather than a wall of dashes. macOS Today is unchanged. Fully localized (English + Spanish).
- **Importing your history is much faster (FER-52).** Importing a multi-year Apple Health export
  used to grind through tens of millions of records doing slow date math on every single one. The
  per-record work is now done with plain integer arithmetic instead of the heavyweight calendar and
  date-formatting machinery, and the daily metrics it writes go in big batches. The result is
  identical — just far less time staring at the import spinner. (FER-8 earlier fixed the memory side
  of this; this one is about speed.)
- **"Today's Synthesis" labels no longer truncate.** On the Today screen, the three at-a-glance
  tiles (Recovery / HRV / Sleep) sit in a tight three-column row. In languages with longer words —
  e.g. Spanish "Recuperación" — the label was clipped to "Recupera…". The label now scales down to
  fit its tile instead of truncating, so the full word always shows.
- **Steadier scores in your first couple of weeks (FER-13).** While NOOP is still learning your
  baseline (roughly your first 4–14 nights), recovery and readiness now lean toward neutral instead
  of swinging hard on a single reading measured against just a few nights of data. Each night your
  baseline firms up, the scores trust your signals a little more, reaching full sensitivity by ~14
  nights. Once your baseline is established, nothing changes — this only tempers the noisy early
  window.
- **A recovery score from your first night with the strap (FER-60).** NOOP used to need about four
  nights before it could show a calibrated recovery score, so a fresh install sat in "calibrating"
  for days. If you've connected Apple Health, NOOP now seeds your personal baseline from your recent
  Apple Health history (overnight HRV, resting heart rate, respiration) so a score can appear on
  night one. The strap always wins: the Apple Health seed is capped to about a week and treated as
  provisional, so your own strap nights take over as they accumulate and the early score stays
  honestly tempered. Apple Watch and the strap measure HRV a little differently, so the first couple
  of days may read slightly off until your strap baseline settles.

_The items below are developer / docs — no user-facing change._
- **Apple Health fallback for Trends & Sleep (FER-62).** `Repository.refresh` reads the `apple-health`
  source as a third, lowest-precedence layer in `mergeDaily` (apple < on-device < imported) and tracks
  the surfaced-from-Apple days in `DashboardData.appleHealthDays` — no `source` column needed on
  `DailyMetric`. Trends badges the HRV / resting-HR cards whose latest point is Apple-sourced; Sleep
  synthesizes a fallback `Night` from Apple's stage minutes (proportional bar, no hypnogram,
  onset–wake hidden) when there's no strap session. `ChartCard` gained an optional `badge` slot.
  `Repository.mergeDaily` is unit-tested (`RepositoryMergeTests`).
- **Apple Health baseline prior (FER-60).** `IntelligenceEngine.analyzeRecent` now folds an Apple
  Health prior (`deviceId: "apple-health"`) UNDER the imported + on-device strap layers when seeding
  the HRV / resting-HR / respiration baselines — filling only days neither strap source covers (the
  existing `== nil` precedence idiom, so the strap always wins). The prior is capped to
  `applePriorMaxNights` (7) so the seeded baseline lands `.provisional`, letting FER-13 confidence
  shrinkage temper the SDNN(Apple)↔RMSSD(strap) HRV scale gap; the 14-night EWMA converges to the
  strap as real nights arrive. Pure helpers `applePriorDays` / `foldApplePrior` are unit-tested
  (`IntelligenceBaselinePriorTests`), and the cold-start contract they rely on is pinned in
  `ColdStartPriorTests`. Efficiency / skin-temp are not seeded (Apple has no comparable signal here).

- **Confidence shrinkage on thin baselines (FER-13).** Added `Baselines.confidence(nValid:)` — a
  weight that ramps linearly from `confidenceFloor` (0.5) at `minNightsSeed` to 1.0 at
  `minNightsTrust`. `RecoveryScorer` multiplies each personal-baseline driver z by it, and
  `ReadinessEngine.zSignal` shrinks its z before flag thresholding, so a barely-seeded baseline
  can't over-react. Trusted baselines (≥ `minNightsTrust`) get weight 1.0 — established scores are
  byte-for-byte unchanged. `DriverBaseline` now carries `nValid` (defaults to trusted for directly
  built priors). 186 StrandAnalytics tests green.
- **Analytics robustness: divide-by-zero guards (FER-36).** Hardened degenerate-input paths in the
  on-device recovery/readiness engine so impossible data can't produce `NaN`/`inf` scores:
  `StrainScorer.pctHRR`/`zoneWeight` now return 0 when the HR reserve is non-positive (restingHR ≥
  HRmax) instead of dividing by zero; the pNN50 divisor (`clean.count − 1`) is guarded explicitly;
  and `RecoveryScorer.recovery` bails to `nil` on a non-finite composite z rather than pushing it
  through the logistic. Added degenerate-case unit tests for each (181 StrandAnalytics tests green).
- **Design system extracted to docs.** The `StrandDesign` Swift package is now mirrored as a
  portable, human- and machine-readable design system under `docs/design-system/`: a documented
  `DESIGN.md` (color, typography, spacing, motion, full component catalog), W3C design tokens
  (`tokens/design-tokens.json`), and a collected `assets/` folder (app icons + brand marks). The
  Swift package stays canonical; these are derived for handoff and cross-platform reuse.
- **Verified the hot database reads are index-covered.** Added `EXPLAIN QUERY PLAN` tests over every
  hot read (metric series, journal, workouts, Apple-daily, daily metrics, sleep sessions, HR samples
  and the HR-bucket aggregate). All reach their rows through the composite primary key or the
  `metricSeries` secondary index — no full-table scans — so no new indexes were needed. The tests
  stay as a regression guard against a future query that silently drops the index.
- **One UI refresh per data refresh, not four.** The dashboard's five separately-published fields
  (days, sleeps, imported sleep, loaded, refresh counter) were folded into a single published value,
  so a data refresh now triggers one SwiftUI invalidation instead of up to four — every screen
  observing the store re-rendered that many times per refresh before. Read sites are unchanged
  (`repo.days` etc. still work); only the internal publishing changed. The deeper
  dashboard-window-vs-full-history split is tracked separately (the cleaner per-property observation
  via the Observation framework is blocked by the macOS 13 deployment target).
- **App Group misprovisioning is no longer a silent no-op (FER-32).** If the App Group entitlement is
  missing, the widget snapshot and the App-Intent pending-action queue previously failed silently —
  the widget/Live Activity just showed nothing with no diagnostic. They now route through one
  `WidgetSnapshot.sharedDefaults()` helper that logs a one-time fault and falls back to standard
  defaults (keeping within-process reads/writes working), so the misprovisioning is visible in
  Release logs instead of invisible. (The HealthKit-day-in-UTC and sync-error-to-UI halves of FER-32
  were already fixed earlier in `b5c0e3b` / `c96df55`.)
- **Imports are cancellable instead of leaking (FER-33).** A WHOOP or Apple Health import ran as a
  fire-and-forget task: if you left the screen or started another import, the old one kept parsing
  and writing in the background with no way to stop it. The in-flight import is now retained and
  cancelled when a new one starts (or via `cancelImport()`), and the importers cooperate — the
  Apple Health XML parse polls for cancellation and aborts mid-file, and both importers bail before
  their database writes — so a cancelled import stops promptly and writes nothing further. A
  cancelled run reports "Import cancelled." rather than a failure.
- **Tabs build on first visit, not at launch (FER-31).** The iPhone tab bar eagerly constructed all
  of its screens at startup — Today, Trends, Live and Sleep each ran its body and its on-appear data
  load before you'd opened them, widening the launch gap. Each tab is now built the first time it's
  selected and kept alive afterward (so switching back is instant), leaving only the Today screen to
  build at launch. No visible change beyond a faster start.
- **Integration tests for cross-source workouts + timezone day bucketing (FER-34).** Added
  `swift test`-runnable coverage for two areas the workout/data pipeline had thin: the storage
  contract behind the cross-source workout merge (the strap / Apple-Health / on-device-detected
  buckets coexisting, source-scoped deletes, the trailing window — `WorkoutMergeStoreTests`), and
  day bucketing across timezone offsets and a daylight-saving switch (`AppleHealthAggregator.localDay`
  — travellers shouldn't see a day split or merged). The pure merge helpers (source classification,
  dismissed-span filter, HR-zone roll-up, unit formatting) already have unit tests; the app-layer
  union glue in `Repository.workoutRows` isn't reachable from CI (the app target has no headless test
  host — only Xcode), so it's exercised here at the store contract it rests on.

---

## 1.84 — iOS: safer strap sync (reliability hardening)

Behind-the-scenes robustness work on the experimental iOS port. No new features and no visible UI
change — the goal is that a strap sync can't quietly corrupt or lose data. Still fully on-device.

- **No more double database setup.** If the app tried to prepare its on-device store twice at once
  (e.g. Bluetooth reporting "powered on" more than once at launch), it could build the store and run
  the database migration twice in parallel. Concurrent callers now join a single setup, so the store
  is created exactly once.
- **History frames can't be reordered or duplicated on a dropped link.** When the strap disconnected
  mid-sync, the queue that feeds historical frames into the database could be left able to spawn a
  second, parallel drain — risking out-of-order or duplicated frames, i.e. corrupted history. There
  is now a single owner for that drain; a disconnect cleanly cancels it instead of racing it.
- **Live HR widget start is regression-proofed.** The guard that prevents two Live Activity starts on
  close-together heart-rate ticks already reset correctly, but its reset now runs via `defer` so it
  can't be skipped by a future code change — keeping the lock-screen Live HR from getting wedged off
  after a failed start.
- **Explore, Insights and Compare open faster on big histories.** Explore used to read every metric's
  full history (thousands of days × ~30 metrics) on entry just to decide which rows get the faint
  "no data" dot — now it asks the database which metrics have any data at all in one quick lookup per
  source. Insights and Compare load their metrics in parallel instead of one after another. The
  numbers shown are unchanged (relationships and overlays still use your full history); the screens
  just stop doing redundant work, so they appear sooner for users with years of data.
- **Large imports write much faster.** Journal answers, workouts and Apple-Health daily rows were
  saved one database row at a time — a big WHOOP export or Health backfill meant tens of thousands of
  separate writes inside a single transaction, which could stall the app mid-import. These now write
  in batches (the same way metric series already did), so a large import lands in a fraction of the
  database round-trips.

## 1.83 — iOS: Today synthesis label no longer clips in Spanish

Work on the experimental iOS port. On-device only, no cloud.

- **"Recuperación" fits its tile again.** On the redesigned Today screen, the "Today's Synthesis"
  tiles show a short label next to a colored status dot. In Spanish (and German) the longer
  "Recuperación" label was being clipped to "Recuper…" because it had to share the tile's width with
  the dot. The label now claims the width it needs before the dot, and gently scales down as a
  fallback on narrower screens, so it reads in full in every language without touching any
  translations.

## 1.82 — iOS: more accurate recovery & readiness

Work on the experimental iOS port. Still fully on-device, no cloud. Imported WHOOP scores are left
untouched; the on-device scores re-derive a little more accurately as the engine re-scores recent
nights.

- **Cleaner nightly HRV.** The heart-rate variability that drives most of your recovery is now
  cleaned of stray (ectopic) beats and summarized with the median across the night, and it's
  measured only while you're actually asleep — wake stretches are excluded. The result is a steadier
  number that reflects your body, not the occasional noisy beat.
- **Smarter overtraining alert.** The training-load balance (acute vs chronic) is now computed on a
  linear load instead of the compressed 0–21 strain scale, so a genuinely hard block reads as the
  spike it is — the injury-risk warning fires when it should.
- **Recovery and Readiness agree.** Both now read your HRV and resting heart rate off the same
  personal baseline, so the two cards no longer tell different stories about the same night.
- **Temperature now counts.** An elevated nightly skin temperature — a classic early sign of illness
  or overreaching — now nudges recovery down and raises a readiness flag, using a signal the strap
  already captured but the score ignored.
- **Sleep judged against your own normal.** The sleep part of recovery is measured against your
  personal efficiency baseline instead of a fixed target, so a naturally lighter sleeper isn't
  penalized every night. All five changes fall back gracefully until your baseline has enough nights.

## 1.81 — iOS: Spanish (es-MX) localization, Apple Health import hardening, Today greeting

Work on the experimental iOS port. All on-device, no cloud — nothing here changes that.

- **Spanish (es-MX) localization (new):** the whole app is translated to Mexican Spanish via the
  String Catalog (`Cenit/Resources/Localizable.xcstrings`), driven by a re-runnable
  `Tools/translate-es.py`, with its own catalog for the widget. The catch was that many labels were
  plain Swift `String`s SwiftUI never extracts (metric titles/categories, readiness/behaviour/stress
  sentences, range pickers, strap-connection states, intelligence notes) — these now go through
  `String(localized:)` at their literal sites, so they actually localize. Longer Spanish labels were
  overflowing the Live/Breathe action buttons; those now scale to fit.
- **Apple Health import — no more OOM crash (fix):** a multi-year Apple Health export is tens of
  millions of `<Record>` elements; the importer used to accumulate every sample in memory (plus a
  dedupe set) and iOS killed the app. Parsing now **aggregates per-day on the fly** (a streaming
  `AppleHealthDayAggregator`), so peak memory is O(days), not O(samples) — measured 2,000,000 records
  at ~104 MB. The reduction rules (mean, max, latest, sum) have a single implementation shared with
  the unit-tested helpers.
- **Import progress + speed (improve):** the import card shows a live record count instead of a
  frozen-looking spinner; the `metricSeries` write is batched into multi-row inserts; and there's a
  free-space guard before decompressing so a too-large export fails with a clear message instead of a
  silent truncation.
- **Localized export filenames (fix):** a non-English iPhone names the export `exportación.xml` (etc.),
  not `export.xml` — the importer now accepts any non-CDA export XML, so imports work regardless of
  device language.
- **Today greeting (new):** the home header shows a time-of-day greeting (Buenos días / tardes /
  noches) with the date beneath, in place of the static "Control Center" title.
- **Leaner Today launch + a latent DB double-open fixed (perf/fix):** profiling the launch path
  showed the dashboard loading its data two-to-three times over — a duplicate `repo.refresh()` (one
  in `AppModel.init`, one in the iOS tab shell) ran a concurrent full-history load and re-fired the
  Today screen's query fan-out, and each sparkline query fetched the full history only to keep the
  last 14/90 days. The launch refresh now has a single owner, the Today queries are windowed in SQL
  and issued concurrently, and `Repository.ensureStore` memoizes store creation — closing a race
  where concurrent first-callers could open and migrate the database twice. (Wall-clock at launch is
  still gated by SwiftUI scene setup, unchanged here; this removes the redundant data work behind it.)
- **Apple Health live sync is now reachable (fix):** the two-way HealthKit bridge (read your Health
  HR/HRV/sleep/SpO₂/steps, write NOOP's strap-derived metrics back) was fully built but had **no UI
  entry point** — `requestAuthorization()` was never called, so the feature was effectively dead. Data
  Sources now has an **"Apple Health — Live Sync"** card with a "Connect Apple Health" button that
  requests permission from an explicit tap (HIG: rationale shown first, never a cold launch prompt),
  then syncs and shows last-synced / errors. Also: a failed read→store upsert during sync no longer
  gets swallowed by `try?` while `lastSync` advances — it now surfaces the error and re-attempts the
  window next time, instead of silently dropping that day's data; a successful sync refreshes the
  dashboard so the imported days appear immediately.
- **Build:** explicit shared Xcode schemes in `project.yml`, so `xcodebuild -scheme Cenit` works in
  a clean checkout / CI without opening Xcode first.

---

## 1.80 — Journal logging + an Imperial/Metric units toggle

- **New (Mac and Android):** a journal card on Insights — quick yes/no chips for behaviours (caffeine,
  alcohol, a late meal, screen time, and your own custom questions) so you can see what moves your
  recovery. Entries stay on-device and are never overwritten by an import.
- **New (Mac and Android):** an Imperial / Metric units toggle in Settings — distance, weight, height
  and temperature, with a separate temperature override. Display-only; stored data is unchanged.

---

## 1.79 — Manual workouts, edit/dismiss auto-detected ones, and CSV export

- **New (Mac and Android):** add a workout by hand, and edit, re-label, or **dismiss** the ones NOOP
  auto-detects — so a misread or duplicate bout no longer sticks around with no way to remove it.
  Dismissals are remembered, so a re-detected session stays hidden.
- **New (Mac and Android):** export all your data as a WHOOP-format CSV bundle (cycles, sleeps,
  workouts, journal) from Settings — yours to keep, and it imports straight back into NOOP.

---

## 1.78 — Fewer false daytime sleeps + an Android sync button

- **Fixed (Mac and Android):** a long sedentary daytime stretch no longer gets logged as sleep —
  daytime periods now need a longer, genuinely low-heart-rate window, while nights and real naps stay
  unchanged.
- **New (Android):** a manual "Sync now" button on the Live screen + an honest progress indicator
  while strap history offloads.
- **Repo:** contributor guidelines, issue/PR templates, a security policy, and build-check CI added.

---

## 1.77 — First-run terms acknowledgment + an Explore chart fix

- **New (Mac and Android):** a one-time, plain-English terms acknowledgment on first launch — what
  NOOP is, that it's independent of WHOOP and that using it may breach WHOOP's Terms of Service, that
  it's not a medical device, and that you use it at your own risk. You accept once; full terms in
  `TERMS.md`.
- **Fixed (Mac):** the Explore metric charts no longer flicker to a straight line when the cursor
  crosses into or out of the graph.

---

## 1.76 — Robust Apple Health import, marginal-radio HR mode, live HR graph

- **Improved (Mac and Android):** a very large Apple Health export no longer fails to import because
  of a single malformed byte — NOOP skips the bad spans and imports everything else, reporting how
  many it skipped. Multi-year exports that errored out before should come in fine now.
- **New (Mac):** if your Bluetooth radio can't sustain WHOOP 4's full realtime stream (older Macs /
  OpenCore), NOOP now falls back to a low-bandwidth standard heart-rate mode, so live HR keeps working
  instead of looping on a dropped connection.
- **Fixed (Mac):** the Health tab's live heart-rate graph now builds a continuous trace over time
  instead of getting stuck on two points.

---

## 1.75 — Personal vital baselines + Mac analytics parity

- **New (Mac and Android):** the Health Monitor now judges each vital — HRV, resting heart rate,
  respiratory rate, skin temperature — against **your own learned baseline** (after ~14 nights),
  not just a one-size-fits-all population range. A personal normal that sits outside the textbook
  band (e.g. a naturally lower HRV) stops reading as "off" when it's fine for you. Falls back to the
  typical range until your baseline is established.
- **New (Mac):** macOS now computes steps, respiratory rate, daily calories and nightly skin
  temperature on-device, matching Android — and nightly respiration now feeds the recovery score on
  both platforms (existing recoveries unchanged when respiration isn't available).

---

## 1.74 — Android reconnect guide + a startup-crash fix

- **Android reconnect guide (parity with Mac 1.73):** if your WHOOP 5.0 / MG can't connect after a
  firmware update (a Bluetooth pairing reset), NOOP now detects it and shows the forget-and-re-pair
  steps right in the app, instead of silently retrying.
- **Fixed (Android):** a rare startup crash on some fast devices (e.g. Galaxy S24+) — the app could
  crash once on launch when a strap was already connected, then open fine on the second try. Mac was
  never affected.

---

## 1.73 — Reconnect help for WHOOP 5.0 / MG after a firmware update

- **If your WHOOP 5.0 / MG stopped connecting after a WHOOP firmware update**, that's a Bluetooth
  pairing reset — not a lockout, and NOOP works fine on the new firmware. To reconnect: quit the
  official WHOOP app, forget the strap in your Bluetooth settings, put it in pairing mode (tap the
  band until the LEDs flash blue), then reconnect. On Mac, NOOP now detects this automatically and
  shows you these exact steps in-app instead of silently retrying. WHOOP 4.0 is unaffected.

---

## 1.72 — GPS workout crash fix (Android)

- **Fixed (Android):** starting a GPS-tracked workout could crash the app on Android 12 and newer.
  GPS needs location permission, which NOOP never requested — and it was capped to older Android
  versions — so route tracking failed the instant it began. NOOP now asks for location permission
  right before a GPS workout and fails safe if it's unavailable: the workout still records heart rate
  and strain, just without a route. If you don't use GPS workouts, nothing changes. (Mac: version
  bump only.)

---

## 1.71 — GPS-tracked workouts (Android)

A community-requested feature, built on the v1.67 manual workout tracking.

- **Pick a sport on start.** Tapping "Start workout" opens a searchable picker (the Health Connect
  exercise-type catalogue, ~21 sports) + a "Track GPS route" toggle that defaults on for distance sports.
- **GPS route / distance / pace** via the platform `LocationManager` (no Google Play Services dependency).
  Live distance + pace show on the workout card; accuracy/teleport filtering via a pure `TrackFilter`.
- **Offline route drawing** — the route is stored as an encoded polyline (`WorkoutRow.routePolyline`,
  Room migration 3→4) and drawn on a blank Compose `Canvas` (`RouteCanvas`) — **no map tiles fetched.**
- **Health Connect writeback** — an `ExerciseSession` (+ `DistanceRecord`) on save, opt-in under Data
  Sources (unions `EXERCISE_PERMISSIONS` into the writeback request; non-fatal if not granted).
- New: `RouteMath` (Haversine/pace/polyline/normalize), `WorkoutSport`/`ExerciseTypes`, `LocationTracker`,
  `RouteCanvas`; `WhoopConnectionService` gains the `location` foreground-service type. Mac: version bump only.
- *Follow-ups:* per-session route on the Workouts screen; screen-off background tracking (dynamic FGS type).

## 1.70 — Clearer sync status + responsive Compare (#91, #93)

- **Android: sync is now visibly in progress.** The Live screen shows a plain "Syncing your strap
  history…" line while the strap offloads, instead of only a brief "· syncing" pill suffix that was easy
  to miss (#91, #93). `LiveScreen.kt`. Mac already surfaced this.
- **macOS: responsive Compare controls.** The time-range pills + Add menu now stack (`ViewThatFits`)
  instead of overflowing on a narrow window — ported from the iOS port's fix. `CompareView.swift`.

## 1.69 — Cleaner Live status + sync diagnostics (#91, #92)

- **Fixed (Mac + Android): "Last Event" no longer leaks plumbing.** The Live status field was showing
  the raw internal event `BLE_REALTIME_HR_ON` (truncated to "BLE_REALTIME_…") whenever live HR started
  — confusing (#92). Both platforms now skip the `BLE_REALTIME_HR_ON/OFF` stream toggle in that field;
  every meaningful event (wrist on/off, double-tap, battery, bonded…) still shows. Swift `FrameRouter`
  EVENT case + Android `WhoopBleClient` non-gesture branch.
- **Diagnostics (Mac + Android): dump rejected-frame hex.** Building on the v1.65 "decoded to 0 rows"
  WARNING — when a history chunk has frames that all fail to decode (CRC / unmapped firmware layout /
  out-of-range timestamp), the Backfiller now logs a hex sample of the first 3 rejected frames (≤64 B
  each). #91 is the first confirmed in-the-wild case (Moto Razr fold, WHOOP 4, layout the v1.66 fallback
  didn't catch) — the count alone can't be decoded, but the bytes let us map the firmware's layout.
  `Backfiller.swift` + `Backfiller.kt` at the WARNING site.
- **Docs:** corrected the stale "macOS AI Coach is sandbox-blocked" claim in README + PRIVACY_SECURITY —
  the distributed macOS build is unsandboxed, so the opt-in Coach works on both platforms.

## 1.68 — Sleep figures, HR zones, charging, calibration (thanks iHateSubscriptions, #88)

A large community contribution (#88), reviewed hard and reimplemented as our own commit onto v1.67.
Eleven small features from a gap analysis against the official app; adopted on both platforms after a
full build-verify (Android suite green, both Swift packages + the macOS app target compile).

- **Imported per-workout HR zones** (Mac + Android): a new "HR Zones" card on Workouts — time-in-zone
  for imported sessions, duration-weighted aggregate labelled approximate. Both parsers tolerate both
  stored key shapes (`z1..z5` Mac / `zone1..zone5` Android).
- **Charging indicator** (Mac + Android): the already-decoded BATTERY_LEVEL charging bit surfaced as a
  "· Charging" suffix on the battery pill; freshness-gated on Android, cleared on disconnect.
- **Prefer imported WHOOP sleep figures** (Mac + Android) on the headline tiles
  (`sleep_performance`/`sleep_consistency`/`sleep_need_min`/`sleep_debt_min`), with the on-device
  APPROXIMATE recompute as fallback. Android premise fix: `parseCycleSeries` now lands those four keys
  as `metricSeries` rows the Explore/Compare UI already referenced but nothing wrote.
- **Real hypnogram** (Android): the Sleep hero renders the stager's persisted per-epoch segments.
- **Recovery cold-start "Calibrating — N of 4 nights"** (Mac): Today ring + synthesis card; retires the
  misleading "0 DEPLETED" empty ring. Pure helper in `StrandAnalytics` (7 Android oracle cases ported).
- **Sync-status surfacing** (Mac): "History synced N ago" / stall warning in Today › Data Sources + the
  menu-bar popover; `relativeAgo` mirrored value-for-value with the Android twin.
- **Illness early-warning notification** (Mac): the opt-in toggle now posts a real system notification on
  the clear→raised transition, once per local day (Android already did). Fixed a double-`requestAuthorization`
  + day-key-set-inside-the-grant-callback bug found in review, so the once-per-day limit holds even if
  notifications were declined.
- **5/MG firmware alarm** (Mac): byte-identical to the hardware-confirmed Android rev-4 golden frame.
  **Experimental on WHOOP 5/MG** — arming is ACKed on hardware, a strap-driven wake-fire has not been
  captured yet; the smart-alarm card now says so. WHOOP 4 path byte-for-byte unchanged.
- **Cleanup**: removed the dead "light-sleep window" stepper (stored but never read — no wake-window
  watcher exists) and `Tools/translate-de.py` now pins UTF-8 (a Windows run had mojibaked the umlauts).
- **Kept the macOS AI Coach.** The contribution proposed removing it for an "offline by construction" Mac;
  we kept it instead — it's opt-in, bring-your-own-key, and works in the distributed (unsandboxed) build,
  so removing a working feature wasn't the right call. Privacy docs already describe it as the one
  transparent opt-in network exception. Gemini provider support (#89) is on the list, on both platforms.

## 1.67 — Manual workout tracking (Mac + Android)

- **New feature: start/stop a workout yourself** (top Reddit request). A "Start workout" button on the
  Live screen (shown when a strap is streaming) opens a live card — elapsed clock, current HR, avg,
  peak, and **strain building in real time** — with an "End workout" button.
- **Built entirely on existing primitives** (no new storage/analysis): captures the smoothed live `bpm`
  into a buffer, scores the window via `StrainScorer.strain(hr:maxHR:sex:)`, and saves a `WorkoutRow`
  (`sport:"Workout"`, `source:"manual"`) via the existing `upsertWorkouts` path — so it appears in the
  Workouts view automatically. Not a double-count: the day's strain already counts that HR (same live
  stream the store persists); the row is a per-session annotation.
- macOS: `AppModel.startWorkout/endWorkout/captureWorkoutSample` (hooked into `ingestHR`) +
  `LiveView.workoutSection`. Android: the mirror on `AppViewModel` + `LiveScreen`. Single buzz on
  start, double on save; a too-short session (no HR captured) is discarded quietly.

## 1.66 — Android: WHOOP 4 unmapped-firmware fallback — the #77 fix

- **Root cause (found via the Goose-PR mining + a cross-platform audit): a real macOS-only fix that
  never reached Android.** macOS `PostHooks "historical_data"` falls back to the canonical **v24
  layout** for an unmapped firmware version and accepts it only if it decodes to physically-real data
  (|gravity|≈1g + plausible HR) — the issue-#30 fix. Android's `HistoricalStreams.decodeHistorical`
  did `histVersionLayout(version) ?: return null` with **no fallback**, so a WHOOP 4 reporting a
  layout version outside {5,7,9,12,24} had **every type-47 record dropped** → the offload "completed"
  (`HISTORY_COMPLETE`), the trim advanced, and **zero data persisted**. Exact match for the #77
  Samsung S23+/Android-16 symptom (sync runs, nothing shows).
- **Fix:** ported the macOS fallback to Android `decodeHistorical` — unmapped version → decode against
  HIST_V24 → keep ONLY if `|gravity| ∈ 0.8..1.2` and `hr ∈ 25..230`, else drop (same as before, never
  garbage). **Strictly dominant:** recovers data the gate proves real, mapped versions untouched, no
  scenario makes any user worse off. Pinned by `HistoricalFallbackTest` (3 cases: mapped still decodes;
  unmapped+real falls back; unmapped+garbage still rejected).
- macOS: **version bump only** (already had it via #30).

## 1.65 — Sync diagnostics: surface silently-dropped history (#77)

- **Observability only — no behaviour change.** `Backfiller.finishChunk` now logs when a chunk arrives
  with frames but `extractHistoricalStreams` returns **zero rows** — i.e. every type-47 frame was
  dropped (CRC fail / unmapped layout / out-of-range timestamp). Previously this acked the trim and
  advanced the cursor while persisting nothing, so a "zero data" strap log showed only healthy
  `acked chunk` lines and the silent loss was **invisible**. Now: `WARNING N frame(s) decoded to 0 rows
  (trim=X) — dropped (CRC/layout/timestamp); nothing persisted`.
- Wired both platforms: Android via a new `log` callback on `Backfiller`; macOS reuses the existing
  `Backfiller.log` sink (which already logs unmapped firmware *versions* — this adds the **aggregate**
  CRC-drop case). Added `Streams.isEmpty` (Swift) mirroring Android `StreamBatch.isEmpty`.
- **Deliberately NOT changed:** the ack/trim behaviour. Refusing to ack an all-dropped chunk would
  wedge the offload in a re-send loop if frames fail CRC systematically — that fix needs a confirmed
  root cause first (a Samsung S23+/Android-16 reporter on #77 is the live case). This release exists to
  make that root cause diagnosable from a user's strap log.

## 1.64 — Android: MTU 247, skin-temp, sync status, recovery UI, alarm groundwork (thanks iHateSubscriptions, #85)

Reimplemented (NoopApp-authored, per our external-contribution policy) from PR #85, rebased on v1.62.
Reviewed part-by-part against current main + the objectivity discipline. **Adopted 4, modified 1, held 1.**

- **MTU 247 (adopt):** negotiate a larger ATT MTU on connect *before* service discovery — the default
  23 caps notifications at 20 bytes and fragments the type-47 offload. Gated discovery on
  `onMtuChanged` with a fallback timeout (a stack that ignores `requestMtu` can't stall connect); the
  once-only discovery kick is an `AtomicBoolean.compareAndSet` (API 26/27 deliver these callbacks on
  binder-pool threads, so the timeout and `onMtuChanged` race).
- **Sync status (adopt):** `lastSyncAt`/`lastSyncError` on `LiveState`, stamped in `exitBackfilling`
  by reason (`HISTORY_COMPLETE` → "History synced N ago"; `timeout` → a non-silent stalled-sync note).
  Pure `relativeAgo` helper + tests. Honest sync truth for a cloud-free app.
- **Skin-temp deviation, offline (adopt):** `AnalyticsEngine.wornNightlySkinTempC` (wear-gated —
  HR-concurrent, in-bed only, 28–42 °C so on-charger ambient drift can't poison the mean) feeds a
  two-pass personal baseline in `IntelligenceEngine` (mirrors avgHrv→recovery), re-deriving
  `skinTempDevC` — which re-arms the illness skin-temp signal. `/100` scale, APPROXIMATE.
- **Recovery cold-start UI (adopt):** `recoveryCalibrationNights` (counts nights with in-bounds HRV,
  matching `Baselines.update`'s validity predicate) → "Calibrating — N of 4 nights" on the ring,
  header and tile instead of a bare "No Data."
- **Named maverick buzz refactor (HELD):** **review catch** — the PR's `notificationBuzz(loops=1)`
  sets the `overallLoop` byte to 1, but our shipped golden frame
  (`…0113012f98…00…`, harshavin hardware-confirmed) has it **0**. The buzz already works; changing a
  proven payload for a refactor is regression risk for zero user value. Kept our inline buzz.
- **5/MG firmware alarm (MODIFIED — experimental-gated):** adopted `AlarmPayload` (`SET_ALARM_TIME`
  rev4 + `DISABLE_ALARM` rev2) + byte-exact tests, and wired `armStrapAlarm`/`disableStrapAlarm` for
  5/MG. But the rev4 layout is **unconfirmed on our side** (no captured `STRAP_DRIVEN_ALARM_EXECUTED`)
  and our own notes deferred it — so arming is **gated behind the Experimental probes opt-in**, not
  the plain smart-alarm toggle: a normal user can never rely on an alarm that might silently not fire,
  while opted-in testers can verify it. (`SET_ALARM_TIME`/`DISABLE_ALARM` added to the 5/MG allowlist.)
- macOS: **version bump only.**

## 1.63 — Mac: strap-computed nights show in Sleep (#77)

- **Fixed (macOS): BLE-computed nights vanished from the Sleep tab** (found from RolandGao's #77
  question "why is last night's analysis in Intelligence instead of Sleep?"). Root cause: TWO
  `stagesJSON` formats exist — imported nights store a **dict of minutes** (`{"light":N,…}`), while
  on-device computed nights store a **segment array** (`AnalyticsEngine.encodeStages` →
  `[{start,end,stage}]`). `SleepView.decodeStages` only parsed the dict, and `latestNight` returned
  nil on failure → **the whole "last night" hero disappeared for Bluetooth-only users** while
  Intelligence (reading DailyMetric) showed the night fine. Fix: `decodeSegments` parses the array
  (mapping the stager's "wake"→awake), and `Night.realSegments` feeds the hypnogram the GENUINE
  timeline for computed nights — strictly better than the synthetic "plausible architecture"
  reconstruction imported nights still get (the export has no per-epoch timeline).
- Android already handled both shapes (`SleepScreen.kt` tries JSONObject then JSONArray) — **version
  bump only.**

## 1.62 — WHOOP 5/MG history: the missing clock (thanks tajchert, #78)

Reimplemented (per our external-contribution policy) from **tajchert's hardware-validated fork branch**
(`whoop5-android-history-sync`), reviewed by a 29-agent adversarial workflow against our v1.61: 25
recommendations verified → 9 adopted, 26 already-superseded, 1 rejected (his CCCD reordering would have
killed standard-0x2A37 live HR).

- **THE unblock — clock before history (Mac + Android):** an un-clocked WHOOP 5 does NOT save sensor
  data to flash (firmware console: "RTC timestamp … is invalid; not saving data to flash"), so offloads
  "succeeded" with metadata only. NOOP now sends SET_CLOCK/GET_CLOCK (WHOOP4's 8-byte payload over
  puffin framing — strap-acked on hardware) after the puffin CCCD drain, before SEND_HISTORICAL_DATA.
  His hardware: 0 → 246 HISTORICAL_DATA frames. Android relocates the post-bond kick to the CCCD-drain
  completion; macOS clocks inside the once-per-connection `whoop5SessionStarted` gate.
- **GET_DATA_RANGE gating, fail-OPEN (Android):** query the stored range first, fire the transfer on
  SUCCESS (result codes 0–3 now decoded; PENDING precedes SUCCESS), 2s fallback because real hardware
  sometimes swallows the first query; one zero-frame retry per connection. Family-aware response offset
  (cmd@10 on 5/MG vs @6 — `strapNewestTs` never updated from 5/MG replies before).
- **5/MG decoders (Android parity + new):** COMMAND_RESPONSE (resp_cmd@10/seq@11/result@12),
  EVENT (+4, payload preserved as hex; BATTERY_LEVEL fields mirrored from Swift), CONSOLE_LOGS
  (UTF-8 @21, 2KB cap) — the strap's console now lands in the strap log ("strap: BLE: PullStats…").
- **Opt-in 5/MG raw capture (Android, default OFF):** `BackfillCaptureJsonl/Summary` (adopted verbatim —
  pure, tested) + append/rotate writer (40k lines/10MB; his truncate-per-session lost overnight data) +
  Settings toggle + consent-headed share sheet. This is the crowdsourcing pipeline for the puffin
  biometric decode (his captures show bulk type-54 = PUFFIN_EVENTS_FROM_STRAP per our PROTOCOL.md, still
  unclassified payload-wise).
- **Post-commit scoring (Android):** a committed backfill chunk schedules a debounced (1.5s)
  `IntelligenceEngine.analyzeRecent` + HC-writeback — fresh history scores in seconds, and scores at all
  in background-only operation (the 15-min loop lives in the Activity-scoped ViewModel).
- **Direct-connect to the OS-bonded 5/MG (Android):** skips the scan (hardware showed first protected
  GATT op failing status=133 on scan-reconnects); stale bonds fall back to a scan via handleDisconnect.
- **isOffloadFrame accepts type 52** (HISTORICAL_IMU_DATA_STREAM) for 5/MG. His EVENT/CONSOLE_LOGS
  progress-counting *removal* is NOT adopted — needs hardware validation (watchdog semantics).
- **Tests:** 4 real-hardware vectors (CRC-pinned Goose command frames, event 0x1D, console text,
  ACK-capture v18 frame: HR 66 / skin 32.38°C / |g|≈1) + capture encoder/summary suites — all green.
- Model selection now survives restarts even with background connection off.

## 1.61 — Android: the widget now actually updates (#82, second find)

- **Fixed: widget starvation under live HR.** The reporter's follow-up symptoms (live HR fine in-app,
  widget frozen at "♥ —"/"⚡ —" with "Connected" underneath, surviving re-adds and reboots, on a Pixel)
  pinned a textbook coroutine bug: the service collected the notification/widget stream with
  **`collectLatest`, whose body is cancelled on every new emission** — and `WidgetSnapshotStore.push()`
  suspends in Glance machinery (`getGlanceIds` + `updateAll`) longer than the ~1 s live-HR emission
  interval. Once streaming started, **every push was cancelled mid-flight, forever**; only the sparse
  post-connect pushes (connected=true, HR/battery not yet present) ever completed — exactly what the
  widget showed. Compounding it, the throttle marked `lastPushAtMs` BEFORE the write, so each doomed
  attempt also burned the 60 s refresh window. The notification was immune (synchronous post).
- **Fix:** `conflate()` + `collect` (process the latest value, never cancel in-flight) + throttle
  decision extracted to a pure `PushGate` (mark **after** save; save **before** the placed-widget
  check so a widget added later renders fresh data; **HR-presence joins the key** so the first sample
  pushes immediately instead of waiting out the window). Regression-pinned by `PushGateTests` (7 tests).
- macOS: **version bump only.**

## 1.60 — Android: notification recovery fix + widget armour (#82)

- **Fixed: the v1.56 notification Recovery %** — `buildNotification` accepted the value but the
  display line was never added, so it computed and silently dropped it. Now rendered ("Recovery NN%"
  between status and battery).
- **#82 ("app keeps stopping" after first widget add, v1.57) — investigated to the metal, NOT
  reproducible:** 10-agent adversarial workflow decompiled Glance 1.1.0's full exception flow
  (receiver `goAsync` catches Throwable→log; SessionWorker exceptions → WorkManager FAILED;
  composition errors → built-in error layout, default `errorUiLayout` is non-zero so the rumored
  rethrow path is unreachable) — **the Glance pipeline cannot kill the process**. Stood up a headless
  Pixel-6/Android-14 emulator and ran 12 scenarios on v1.59 **plus the exact repro on a fresh v1.57
  install** (real launcher drag-and-drop first-ever widget add → repeated app returns): zero crashes,
  stable PID. Verdict: environment-specific to the reporter's device, self-resolved after update;
  no behavioral change justified (objectivity rule).
- **Defence-in-depth shipped anyway** (belt-and-braces, honestly labelled): `.catch{}` on the
  service's notification combine (a Room error in `daysMergedFlow` WOULD have propagated uncaught out
  of `scope.launch` — real latent risk, just not #82), `onCompositionError` override rendering our own
  fallback layout (friendlier than Glance's generic one), `runCatching` around the widget's pref load.
- **Dependency currency:** `glance-appwidget` 1.1.0→**1.1.1**; explicit
  `androidx.work:work-runtime-ktx:2.9.0` pin (Glance's POM drags in 2.7.1 from Oct 2021 — pre-Android-14;
  2.9.x is the compileSdk-34 ceiling).
- macOS: **version bump only.**

## 1.59 — Android: share back to Health Connect (opt-in)

- **New (Android): Health Connect writeback** — new `HealthConnectWriter` pushes NOOP's **computed**
  nightly metrics (resting HR, HRV RMSSD, SpO₂, respiratory rate; last 60 days) into Health Connect.
  Two deliberate scope limits: **computed days only** (`repo.days(computedDeviceId)` — imported
  WHOOP-export/HC rows are never echoed back, which would duplicate another app's data or loop our own
  import), and **idempotent by `clientRecordId`** (`noop-<metric>-<day>` + write-time
  `clientRecordVersion`, because HC does NOT auto-dedupe re-inserts the way HealthKit does — the
  latest computation always wins, no stacking). Four `WRITE_*` permissions added to the manifest,
  requested only when the user opts in; denial flips the toggle back off. **Default OFF** — "Share
  back to Health Connect" toggle in Data Sources; while on, every 15-min recompute re-writes
  (runCatching-guarded so an HC hiccup never breaks the analysis loop).
- macOS: **version bump only.**

## 1.58 — Android: bottom tab bar

- **New (Android): bottom `NavigationBar`** — Today / Trends / Live / Sleep as permanent tabs, plus a
  **More** tab opening a `ModalBottomSheet` that renders the *same* `drawerGroups` the hamburger drawer
  shows (verbatim — one source of truth, both routes reach every screen). The drawer is kept untouched
  for reversibility; the bar is purely additive. The More tab lights up whenever the current screen
  isn't one of the four tabs, so the bar never shows "nowhere". All navigation through the existing
  `navigateTopLevel` (single-top + state save/restore — back behaves the same).
- macOS: **version bump only.**

## 1.57 — Android home-screen widget

- **New (Android): home-screen widget** — today's recovery (band-coloured 67/34), live HR and strap
  battery, tap-to-open. New `com.noop.widget` package on Glance (`glance-appwidget:1.1.0`, the last
  line compatible with compileSdk 34): `NoopGlanceWidget` renders purely from a SharedPreferences
  snapshot (no BLE/DB at compose time, survives process death), `WidgetSnapshotStore.push()` throttles
  (meaningful-change immediate, HR at most 1/min — Glance re-inflation is far heavier than a notify())
  and no-ops when no widget is placed. Two producers: `WhoopConnectionService`'s v1.56 combine (the
  heartbeat while the UI is closed) and `AppViewModel.recentDays` (foreground with the service off).
  `updatePeriodMillis=0` — push-only, the OS never polls. Receiver `exported="true"` as the launcher
  requires.
- macOS: **version bump only.**

## 1.56 — Shortcuts on Mac, recovery in the Android notification

- **New (macOS): App Intents / Shortcuts actions — "Buzz Strap" and "Mark a Moment."** New
  `Cenit/System/NOOPAppIntents.swift` exposes both as `AppIntent`s with an `AppShortcutsProvider`, so
  they're available from Shortcuts.app, Spotlight, and menu-bar/keyboard triggers without opening the
  window. They reach the live bonded strap via a new `static weak var AppModel.shared` (published in
  `AppModel.init`) — constructing a fresh `AppModel` from an intent would spin up a second BLEManager +
  analysis loop and could never buzz. Guarded: a fired intent with NOOP closed throws "open NOOP first";
  with the strap unbonded, "connect your strap." macOS 13+, **no new entitlement or Info.plist key**.
  The inbound counterpart to the existing outbound double-tap→Shortcut path (#42 idea-mining).
- **New (Android): today's recovery % in the foreground-service notification.**
  `WhoopConnectionService` now `combine`s `ble.state` with `repo.daysMergedFlow("my-whoop")` and appends
  "Recovery NN%" to the ongoing notification's detail line (alongside live HR + strap battery). It
  re-posts when the 15-min `IntelligenceEngine` recompute lands, and stays absent until enough nights
  are scored. `runCatching`-guarded; near-zero blast radius (notification copy only).

## 1.55 — Mac: recovery builds from your strap alone (#78)

- **New (macOS): BLE-only recovery cold-start — parity with Android v1.53.** `IntelligenceEngine.swift`
  now runs **two passes** (harvest each offloaded night's baseline-independent avgHrv/restingHr, seed
  the baseline from the union of imported + on-device nightly values, re-score recovery). So a
  Bluetooth-only Mac user crosses `Baselines.minNightsSeed` (4 nights) and recovery lights up without a
  WHOOP import; honest-null until then; imported values still win per day (only-if-absent fill).
- **macOS: WHOOP5 `step_motion_counter` now persists** (`StepSample` in WhoopProtocol Streams + routed in
  `extractHistoricalStreams` + WhoopStore **v10 migration** — additive, no destructive fallback). Decoded
  but previously dropped on Mac. Surfaced later; still APPROXIMATE. `StepSampleTests` pins the round-trip.
- **Deferred (objectively): the skin-temp `/100` vs `/128` scale.** Both platforms store the **raw**
  register and both real frames sit in the *overlap* of the two gate bands, so it's a **latent**
  divergence, not a bug — and the obvious unification (`/128`, 20–45) would reject the off-wrist frame
  and break the wrist-contact parity test. Left as-is pending a real calibration decision.
- Android: **version bump only** — it already had recovery seeding and step persistence (v1.53).

## 1.54 — French WHOOP exports now import (#79)

- **Fixed: a French WHOOP export imported 0 items.** Third localisation after German (#3) and Spanish
  (#76). A French export translates **both** the column headers (`Score de récupération %`,
  `Variabilité de la fréquence cardiaque (ms)`, `Durée du sommeil paradoxal (min)`, …) **and** the
  sleep/workout filenames (`sommeil.csv`, `entrainements.csv`) — so nothing matched.
- NOOP now maps the **full** French column set, including the complete **workouts** file (HR zones,
  activity name/strain) — the reporter supplied all three header rows, so French is more complete than
  Spanish out of the gate. Two French quirks handled by the normaliser (both fold to `_`): the
  apostrophe in `Niveau d'oxygène` / `Temps d'éveil` (straight `'` **and** curly `’`), and the
  **non-breaking space** before `%` in the `Zone FC 1 %` workout headers. `physiological_cycles.csv`
  keeps its English filename but French columns; both handled. Mac + Android. Real-header parse +
  normalisation tests pin it (incl. the apostrophe + NBSP cases); verified with `swift test`.

## 1.53 — Recovery builds from your strap alone, Android (#78)

- **New (Android): BLE-only recovery cold-start.** The recovery baseline only ever seeded from
  *imported* nightly history, so a Bluetooth-only user (no WHOOP CSV) never crossed
  `Baselines.minNightsSeed` (4 valid nights) and recovery stayed blank forever — even with offloaded
  nights sitting in the store. `IntelligenceEngine` now runs **two passes**: pass 1 computes each
  offloaded night's baseline-*independent* aggregates (avgHrv / restingHr via SleepStager+AnalyticsEngine),
  pass 2 seeds the baseline from the **union of imported + on-device nightly values** and re-scores only
  the cheap recovery composite. So recovery lights up from the strap's own nights after ~4 nights; it
  stays honestly null until then; a real import still wins per day. The natural payoff of v1.52's offload.
- **Under the hood (landed dark — computed/stored, not yet surfaced, pending hardware validation):**
  - `stepSample` table + `dailyMetric.steps` / `activeKcalEst` columns via a **real additive Room
    migration** (`MIGRATION_2_3`). **The `.fallbackToDestructiveMigration()` is removed** — with
    `exportSchema=false` a hand-written-SQL mismatch would otherwise *silently wipe* already-acked,
    non-resendable strap history; now Room throws loudly instead. The migration SQL was **verified
    byte-for-byte against Room's generated schema** before shipping.
  - The WHOOP5 `step_motion_counter@57` (decoded but previously dropped) now persists; `AnalyticsEngine`
    derives a daily step total + an APPROXIMATE whole-day HR→energy estimate; detected workouts persist
    under the `-noop` id (deduped against imported workouts). All clearly APPROXIMATE; **the steps tile
    stays dark** until @57's semantics are validated against the official app.
  - **Fixed a respiratory-rate band mismatch:** `SleepStager.respRateFromRR` could emit 6–8 bpm, but every
    consumer (`ReadinessEngine` illness/readiness) only acts on 8–25 — so a sub-8 estimate was
    persisted-then-silently-ignored. The band is now a single canonical source (`respPlausibleRangeBpm`,
    owned by the producer, referenced by the consumer); RSA NaNs anything outside it before persisting.
  - Conservative resp gates (size ≥ 10, raised z-thresholds, 2+ flags to fire) so the noisier on-device
    RSA can't trip false illness/readiness flags.
- Reimplemented onto current main from community PR #78 (credited), with the migration-safety + RSA-band
  fixes applied. v1.48–1.52 work untouched.
- macOS: **version bump only** — it has the same single-pass-baseline gap; recovery-seeding parity is a
  tracked follow-up.

## 1.52 — WHOOP 5.0/MG history offload, Android (#78)

- **New (Android, experimental): WHOOP 5.0/MG historical offload** — Android reaches parity with the
  Mac, which already had this. A 5/MG can now download its stored history (not just stream live HR),
  which is what feeds recovery / strain / sleep.
- **The fix that made it actually work.** The 5/MG "puffin" envelope shifts the inner record **+4** vs
  4.0, and its HISTORY_END/COMPLETE marker is **`PUFFIN_METADATA` (type 56)**, not 49. Android's
  offload-frame check read `frame[4]` with `{47,48,49,50}` — so on a real strap **every** history-closing
  frame was dropped as live-flood, no chunk ever committed, the strap never trimmed, and the offload
  idle-watchdog timed out: zero history. NOOP now reads the type at `frame[8]` for 5/MG and accepts
  `{47,48,49,50,56}` — matching the hardware-proven Swift path (`BLEManager.isOffloadFrame`,
  `BLEManager.swift:500`). Ported pieces: family-aware `isOffloadFrame`, `decodeMetadataWhoop5`
  (meta_type@10 / unix@11 / trim_cursor@21), `Backfiller.begin(family)` + `endData` (+4 → `frame[21:29]`),
  the 5/MG `send()` allow-list (`SEND_HISTORICAL_DATA` + `HISTORICAL_DATA_RESULT`, framed as puffin
  commands), and the 5/MG post-bond offload kick (the CLIENT_HELLO ack now marks the handshake done,
  which gates the offload). A new `Whoop5OffloadTest` pins the type-56 case the original PR's tests missed.
- **Experimental — please verify on a real strap.** The offsets are cross-confirmed (Swift + Linux tool +
  the hardware-anchored +4), but no captured 5/MG HISTORY_END frame exists in-repo, so 5.0/MG owners:
  please report whether your history actually populates end-to-end. Reimplemented from a community
  contribution (#78), credited; the v1.48–1.51 reliability work (write queue, resubscribe, sync pill,
  family-gated battery) is untouched.
- macOS: **version bump only** — its 5/MG offload path was already complete and hardware-verified.

## 1.51 — True battery %, a sync indicator, and HR on imported workouts (#77)

- **Fixed: battery flashing 100% then correcting (or reverting to 100%).** The WHOOP 4.0 exposes the
  standard Battery Level characteristic (0x2A19) but it's a **stub that always reports 100** — the real
  charge only comes from the proprietary `GET_BATTERY_LEVEL` response (u16/10). NOOP read **both** into
  the same display with no priority, so 0x2A19 landed first (100%) and the real value corrected it a
  beat later — and since 0x2A19 is also *subscribed*, a stray stub notification could revert a true 94%
  back to 100%. Battery now comes **only from the real source per family**: WHOOP 4 = the proprietary
  command; 5.0/MG = 0x2A19 (unchanged — its proprietary command isn't framed). On macOS this also stops
  the stub 100 polluting the low-battery alert hook. Mac + Android.
- **New: "Syncing strap history…" indicator** (Mac + Android). While a historical offload runs, Today /
  Sleep / Intelligence's empty states show a pulsing pill with a live **chunks-pulled count** (a count,
  never a percent — total pending is unknowable from the protocol), so "No nights here yet" mid-sync
  reads as in-progress rather than final. The Live pill shows **"Bonded · syncing"**. `LiveState` now
  publishes `backfilling` + `syncChunksThisSession` (Android republishes every 10th chunk so the
  foreground-service notification isn't re-posted at chunk rate); cleared on session end AND on
  disconnect so the pill can't stick on.
- **Fixed (Android): imported workouts showed no HR.** Health Connect `ExerciseSessionRecord`s carry no
  summary HR, so the importer stored `avgHr/maxHr = null` and the Workouts list rendered "–" forever.
  Two-part fix: (a) the **importer** now intersects each session's window with its `HeartRateRecord`
  samples (targeted per-session reads, one bad session can't fail the import) and stores real avg/max;
  (b) **display fallback** — Workouts/Today fill a null-HR imported session from the strap's own ~1 Hz
  samples over the workout window (new indexed `hrWindowStats` aggregate; ≥60 samples required so strays
  can't fabricate an average; display-only so a re-import can't be clobbered; capped per load). Demo
  flavor unaffected (its seeded workouts always carry HR).

- **Fixed (Android): sustained command-write congestion on slow GATT stacks.** A Pixel 7 on Android 16
  logged ~56 `writeCharacteristic busy` retries **and 6 hard `dropped after 6 retries`** in ten minutes
  (v1.48). Two changes:
  - **Bigger, escalating write-retry budget** — `MAX_WRITE_RETRIES` 6 → 12, and the backoff now grows
    per attempt (12, 24, … capped ~96ms) so a stack that's busy for a while gets time to clear instead
    of exhausting the budget in ~70ms. Nothing hard-drops.
  - **Re-subscribe at most once per quiet episode.** The keep-alive re-subscribed all notify chars on
    every 30s tick while the stream was quiet, flooding descriptor writes that collide with the command
    queue (Android serves **one** GATT op at a time across reads/writes/descriptors). It now re-subscribes
    once per quiet spell and re-arms when data next arrives — a dropped CCCD is still recovered, the churn
    is gone.
- Context (from #77): the "no overnight scores" reports are usually an **empty strap buffer** — the
  official WHOOP app, bonded overnight, trims the strap's history as it syncs, so NOOP finds little to
  offload. The reliable history path is the WHOOP CSV import. This release fixes the *separate* congestion
  bug those logs surfaced.
- macOS: **version bump only** (CoreBluetooth queues GATT ops internally).

- **Fixed: a Spanish WHOOP export imported 0 items.** WHOOP's Spanish export translates **both** the
  column headers (`Puntuación de recuperación (%)`, `Variabilidad de la frecuencia cardíaca (ms)`, …)
  **and** some filenames (`sueño.csv`, `entrenamientos.csv`) — so the filename match missed the sleep/
  workout files and the column match missed every translated header, giving "Imported 0 items."
- NOOP now maps the full set of Spanish column headers (supplied from a real export, #76) onto the
  canonical fields, and recognises the Spanish filenames — so recovery, RHR, HRV, skin temp, blood
  oxygen, day strain, every sleep stage, nap, etc. all import. `physiological_cycles.csv` keeps its
  English filename in the Spanish export but its columns are Spanish; both cases are handled. The
  content-sniffer also classifies the Spanish sleep file by its (now-aliased) columns.
- Same approach that added German (#3). Workout column names are inferred from WHOOP's consistent
  Spanish pattern; an unmatched alias simply never fires, so it's safe. Mac + Android. A real-header
  parse test pins the values. Verified with `swift test`.

- **Fixed (Android): dropped Bluetooth commands on stricter stacks (Android 13+, worst on Android 16).**
  When the phone's GATT stack was momentarily busy it would reject a command write, and NOOP **dropped**
  it instead of retrying. The dropped frame was often the one that **starts live HR**, **sets the strap
  clock**, or **acks a history chunk** — so live HR sometimes never started and overnight data never
  landed, even with a healthy strap and pairing. NOOP now **retries a rejected write** (bounded backoff,
  preserving command order) and **paces** without-response writes so the stack keeps up.
- Diagnosed from a detailed strap log: a Pixel 7 on Android 16 whose offload completed cleanly but whose
  `TOGGLE_REALTIME_HR` / `SET_CLOCK` writes were being rejected and dropped.
- macOS: **version bump only** — it relies on CoreBluetooth's own write queue and was never affected.

## 1.47 — Auto-sync Health Connect (Android)

- **Opt-in Health Connect auto-sync (Android).** Turn it on under Data Sources → Health Connect and NOOP
  re-pulls new Health Connect data (e.g. a Samsung Galaxy Watch → Samsung Health → Health Connect) each
  time you open the app, if the last sync is older than your chosen **6 / 12 / 24h** interval. Read-only,
  idempotent, **never overwrites richer strap data**, **default OFF**. Adopted from a community PR.
- Deliberately **on-open only** (no background worker): the contributed version also added a WorkManager
  background job, but that's best-effort on Android 14+ and needs a sensitive background-health
  permission — so we took the reliable foreground catch-up and skipped the worker + the permission.
- macOS: **version bump only** (HealthKit doesn't exist on macOS; the Mac path stays the export import).

## 1.46 — Revived-strap history dates, gestures during sync, clearer pairing state

- **Stale-strap clock correction (#72).** A strap that sat unused has a drifted RTC, so its offloaded
  history landed months in the past — live HR worked, but recovery/strain/sleep never showed as "today."
  `extractHistoricalStreams` now corrects type-47 + EVENT timestamps by the strap-vs-real clock offset
  **only when the strap clock is clearly stale (>1 day off)**, snapped to a 5-min grid so the correction
  is deterministic across re-syncs (rows dedupe by timestamp). No-op for a normal strap. Both platforms.
- **Live gestures during a history sync (#69).** `isOffloadFrame` classed EVENT(48) as bulk-sync
  traffic, so during a backfill a real-time double-tap / wrist event was routed to the sync handler and
  never fired — for minutes at a time on a 5.0/MG. NOOP now fires live gestures even mid-sync, gated on
  the event being recent **in the strap's own clock domain** (macOS) so a *replayed historical* gesture
  from the offload doesn't fire; Android fires live gestures ungated and gates only during a backfill.
- **"Encrypted bond" vs "live HR" indicator (#69).** On a 5.0/MG, live HR streams over the open
  Bluetooth profile without a real encrypted bond, so the app used to say "Bonded" when it wasn't. The
  Live pill now shows **"Bonded"** only for a genuine encrypted bond, else **"Live HR (not fully
  paired)"** — the encrypted bond is what unlocks buzz, alarms, double-tap and history sync. The in-app
  pairing tip now mentions tapping the band to enter 5.0/MG pairing mode. Both platforms.
- _Known, tracked limitations:_ a strap that's both clock-stale and mid-offload may miss a double-tap
  during that sync window on Android (no GET_CLOCK correlation to gate in the strap's clock domain); and
  a record re-offloaded across a successful SET_CLOCK could store twice (proper fix = persist the
  per-device offset). Both narrow.

## 1.45 — Clearer pairing guidance for WHOOP 5.0/MG (Mac, #69)

- **A 5.0/MG streams live heart rate before it's fully (encrypted-)paired** — and buzz, alarms,
  double-tap and full history sync all need that real pairing. NOOP now keeps the "free the strap
  from the WHOOP app" guidance visible (in clearer wording) whenever the strap isn't fully paired,
  instead of hiding it once live HR appears — so it's obvious what to do to unlock the rest (#69).
- This **reverts v1.44's over-eager hint-clearing**: on a 5/MG, `bonded` is also set by the live-HR
  shortcut (HR rides the unbonded standard profile), so clearing the hint there hid the *accurate*
  "free the strap" guidance from users who were streaming HR but never got the real encrypted bond.
  The hint now only clears on a genuine bond (the `CLIENT_HELLO` ack) or a fresh connect attempt, and
  the banner is reworded from "Pairing refused" to guidance.
- Android: **version bump only** (the banner is macOS-only).

## 1.44 — Fixes a false "pairing refused" warning (Mac, #69)

- **The "Pairing refused" banner no longer cries wolf on a working connection** (Mac). It could stay
  up on the Live screen even after the strap had bonded and live heart rate was streaming — a stale
  warning on a link that was actually fine (reported by a 5.0/MG owner, #69). `LiveState.pairingHint`
  now clears on every bond-completion path (a `didSet` on `bonded`), so it disappears the moment the
  link bonds.
- Android: **version bump only** (the banner is macOS-only).

## 1.43 — 24-hour heart-rate trend on the dashboard

- **See your whole day's heart rate on Control Center** (Mac + Android). A new full-width trend plots
  your continuous heart rate across today, read straight from the strap's own ~1 Hz history — so it
  fills in even for the hours the app was closed, not just while it's open.
  - **Downsampled in SQL**: a fully-worn day is ~86k samples at 1 Hz, so the chart reads 5-minute
    bucket means (`GROUP BY ts/300`) rather than loading every row — a new `hrBuckets()` on both the
    GRDB store and the Room DAO. The day's low / average / high sit under the chart.
  - Hidden until there's wear today, so a strap with no readings yet shows nothing rather than an
    empty axis. Works on WHOOP 4.0, and on 5.0/MG (its live HR feeds the trend too).

## 1.42 — Auto-reconnect to your strap on launch (Android, #67)

- **NOOP reconnects to your strap automatically when the app starts** (issue #67 — jamartif: after an
  APK update the band stayed disconnected until you tapped Connect). The process restart on an update
  (or any cold launch) left the app disconnected because there was **no auto-connect on launch** and
  **no persisted strap** — every `connect()` was user-tapped, and the v1.36 reconnect used an
  in-memory device that's gone after a restart.
  - **Persist the bonded strap**: `NoopPrefs.setLastDevice(address, model)` on the bonded transition
    (on-device only, never sent); cleared on a model switch.
  - **Reconnect on launch**: `AppViewModel.autoReconnectOnLaunch()` (called from `init`) →
    `WhoopBleClient.reconnectToAddress()` does a direct `connectGatt(autoConnect=true)` to the saved
    strap — no scan; the OS connects as soon as it's in range. Gated on **"Keep connected in the
    background"** + a previously-bonded strap; no-ops if already connected or the runtime BT permission
    isn't granted.
- macOS: **version bump only.** It has the same gap (CoreBluetooth state restoration isn't actually
  enabled — `CBCentralManager` is created without a restore identifier), but it's lower-value there (the
  menu-bar app stays alive, updates are infrequent) and adding it needs a gating decision (no
  keep-connected pref exists on macOS). Tracked as a follow-up.

## 1.41 — Update check shows what's new

- **The "Check for updates" result now previews what's new.** When a newer version is found, the
  result expands to show the release's notes (the changes, with the Downloads/footer boilerplate
  trimmed and the heaviest markdown stripped, capped + scrollable) alongside the Download button — so
  you can see what you're getting before tapping through. The `body` is already in the
  `releases/latest` response, so this is the same single request; `cleanNotes()` does the trimming on
  each platform. No new network behaviour.

## 1.40 — Check for updates (both platforms)

- **New: a manual "Check for updates" button** in Settings → About. One user-initiated GET to the
  PUBLIC GitHub releases API (`api.github.com/repos/NoopApp/noop/releases/latest`) — compares the
  `tag_name` to the installed version and, if newer, shows a Download button that opens the release
  page; otherwise "You're on the latest." Graceful failure on offline/rate-limit. **No background
  polling, no auto-update, nothing about the user is sent** — it only runs on tap, and only reads a
  version number.
- **Version comparison is unit-tested** on both platforms (`VersionCheck.isNewer` in WhoopProtocol;
  `UpdateCheck.isNewer` on Android) — it compares dot-separated numeric segments so `1.40 > 1.39` and
  `1.9 < 1.10` (a plain string compare gets both wrong), tolerant of a leading `v` and the demo
  flavour's `-demo` suffix.
- **macOS posture note:** this is the first feature to make an outbound connection, so the macOS
  sandbox entitlement `com.apple.security.network.client` was added. It's used only for this
  user-tapped check and the opt-in, off-by-default AI Coach — there is no automatic/background traffic.
  Android already declared `INTERNET` (for the opt-in Coach), so it needed no change.

## 1.39 — Wrist alerts for incoming calls (Android, #66)

- **Buzz on incoming calls** (community PR #66 by DieserLiton; reimplemented as NoopApp). A dedicated
  **Calls** section in Notifications settings, separate from per-app alerts:
  - **Native phone calls** via a `PhoneCallReceiver` (READ_PHONE_STATE), and **best-effort VoIP** via the
    existing notification listener (`VoipCallClassifier`, an 8-app allowlist). One coordinator
    (`CallAlertController`) drives a bounded repeat cadence — immediate, then every 8s, max 4 buzzes.
  - **Privacy contract intact** — reads only the phone *state* string (`RINGING`/`OFFHOOK`/`IDLE`, never
    `EXTRA_INCOMING_NUMBER`) and a tiny set of notification *metadata* (package / `CATEGORY_CALL` / flags),
    never the number, caller, title, text, or extras; no `READ_CALL_LOG`/`READ_CONTACTS`; nothing
    sensitive logged. `READ_PHONE_STATE` is requested **only** when the user enables "Phone calls".
  - Reuses the shared component system; the existing per-app wrist-alerts are untouched.
- **Two correctness fixes applied on adoption** (from the review):
  - `CallAlertController` now has a **self-healing 60s max-ring watchdog** — a dropped `PHONE_STATE=IDLE`
    broadcast or a missed `onNotificationRemoved` could otherwise leak a token and silently kill the next
    call's alert until a process restart. It auto-clears (re-armed on each sign of life).
  - An incoming VoIP call is now routed to the **Calls path only** (always returns), so a call from an app
    that's also enabled as a per-app alert can't **double-buzz**.

## 1.38 — Responsive during long history syncs (Mac, #64 / #65)

- **Mac stays responsive during long historical offloads and dashboard analysis** (community PRs #64,
  #65 by rr-allin; both verified against current `main`, symbols + the buzz path intact):
  - **#64 (`BLEManager.swift`)** — offload frames are treated as bulk sync, not live UI traffic:
    during a backfill, type-47/48/49/50/56 frames bypass the live `FrameRouter` and feed only the
    `Backfiller`, drained in small batches (12) with `Task.yield()` between slices so SwiftUI can
    paint. HISTORY_END ack logging is throttled (ack #1, then every 25th). `beginBackfill()` now
    returns whether it actually started, so a deferred backfill no longer stamps `backfillLastAt`
    (which would rate-limit a sync that never ran). Live HR (type-40) and the GET_DATA_RANGE liveness
    watchdog still flow through the live path — unaffected.
  - **#65 (`AppModel.swift`, `IntelligenceEngine.swift`)** — a completed backfill now refreshes the
    dashboard cache (`repo.refresh(days: 120)`) instead of immediately running full analysis;
    `analyzeRecent` early-returns if an analysis is already in flight (guarded on the existing
    `computing` flag); `AnalyticsEngine.analyzeDay` runs in a utility-priority detached task with a
    `Task.yield()` between days — so the heavy recovery/strain/sleep compute no longer stalls the main
    actor.
- Mac-only changes; Android gets the lockstep version bump.

## 1.37 — New first-run onboarding, Mac + Android parity (#36 / #63)

- **A unified 11-step first-run onboarding** on both platforms (Welcome · What it does · Expectations ·
  Bluetooth · Wear · Connect/Scan · **Bonded** celebration · Profile · Import · **Notifications** · Done),
  reimplemented from community PR #36 (by Brechard; design in #63). Highlights:
  - **Contextual permissions (Android)** — nothing fires at launch; Bluetooth is requested only when
    leaving the "before you connect" screen, scanning goes through the shared `BlePermissions.kt` gate
    (the same one Live/Settings use), and notifications are requested on the Notifications step's CTA.
  - **Bonded celebration** auto-advances once the strap bonds (skipped when nothing is bonded); the
    **foreground-connection service is promoted only on completion**, not mid-flow.
  - **Parity/polish** — config-change-safe nav (`rememberSaveable`), typed import-failure styling on both
    platforms (incl. a macOS Data Sources green-on-failure fix), `+/−` steppers for the profile (the two
    `StepperField`/`StepperButton` helpers promoted from Settings into the shared `Components.kt`), shared
    component system + `Metrics.*` spacing, chrome uses `accent` rather than the data-reserved recovery ramp.
  - Verified on adoption: every recent fix survives untouched (HR-spike smoothing #46, smart-alarm bond
    re-arm #59, the Re-scan permission gate #1, the buzz), the `connect(promoteService:)` change is
    backward-compatible, and the unused `GhostButtonStyle` was dropped.
- **Live HR zones use your real max heart rate.** `HealthScreen` now reads `ProfileStore.hrMax` (your manual
  override, else the age-based Tanaka estimate) for live zone/%-max instead of a hardcoded `190` — committed
  separately from the onboarding change.

## 1.36 — Android: direct reconnect after a dropout (#61)

- **Fixed (Android): a dropped WHOOP 4.0 could get stuck "disconnected" and never reconnect** (issue
  #61). `handleDisconnect` only ever called `connect()` → a BLE **scan**, but a bonded strap that the
  OS still holds (or that simply isn't advertising) doesn't show up in a scan — so it looped
  `No WHOOP strap found` until the user forced the strap into pairing mode. Now the client **remembers
  the connected `BluetoothDevice`** and, on an unintentional drop, reconnects to it **directly** via
  `connectGatt(autoConnect = true)` — the OS reconnects as soon as the strap is reachable, with no
  scan and no advertisement needed. `connectToDevice` gained an `autoConnect` param (default `false`
  for the scan-discovered first connect) and now closes any stale GATT first; `prepareForModelSwitch`
  clears the remembered device so a model switch scans fresh.
- macOS already did this — `connect()` reconnects via `retrieveConnectedPeripherals` + `central.connect`
  (and state-restoration) before falling back to a scan — so this is an **Android-only** fix +
  lockstep version bump.

## 1.35 — WHOOP 5/MG buzz matched byte-for-byte (#48)

- **WHOOP 5.0/MG haptics now byte-identical to a working app.** v1.34 fixed the opcode (`0x13`) but
  kept the WHOOP-4.0 payload. The contributor's working 5.0 app ("whootify") was decompiled, giving
  the real command:
  - **Payload**: `[0x01, effects(8), loopControl(u16 LE), overallLoop]` — 12 bytes. We send the
    "notify" preset (effects `47,152`): `01 2f 98 00 00 00 00 00 00 00 00 00`.
  - **Framing fix — `pad4`**: the strap's maverick framing pads the inner record to a 4-byte boundary
    before length+CRC. `puffinCommandFrame` *wasn't* doing this — it didn't matter for the 4-aligned
    commands shipped so far (toggle-HR, historical), but the 12-byte haptic inner is 15 bytes and must
    pad to 16, or the declared length + CRC32 are wrong and the strap rejects the frame. Added pad4 to
    `puffinCommandFrame` on both platforms (no-op for the aligned commands — existing frames unchanged).
  - **Verified byte-for-byte**: a golden-vector test on each platform asserts `puffinCommandFrame(0x13,
    seq=1, notify-payload)` equals the frame the working app's `buildMaverickFrame` produces
    (`aa0114000001e1e1230113012f98…98cb83a5`), and that pad4 leaves HR-toggle's frame at 16 bytes.
- So a bonded 5.0/MG should now actually vibrate on Test buzz / wrist alerts / smart-alarm buzz.
  **WHOOP 4.0 buzz is byte-for-byte unchanged** (still opcode 79 + its own frame). Awaiting hardware
  confirmation on #48.

## 1.34 — WHOOP 5/MG haptics opcode (experimental, #48)

- **Experimental (WHOOP 5.0/MG): buzz now sends opcode `0x13`, not the 4.0 `RUN_HAPTICS_PATTERN`
  (79).** Decoding @james-e-morris's real-MG puffin capture showed the strap **rejecting** our
  opcode 79 (`COMMAND_RESPONSE result=0x03`, while every accepted command — toggle-HR `0x03`,
  historical `0x16`/`0x17` — returns `0x01`), and a working third-party 5.0 app fires the buzz with
  opcode **`0x13` (19)** (`PENDING → HAPTICS_FIRED → SUCCESS`, `VALID_PATTERN`). The `send()` puffin
  branch now overrides **only the opcode** for `runHapticsPattern` on `.whoop5` (`0x13`); the payload
  is still the 4.0 preset `[patternId, loops, …]` pending the exact 5/MG payload (incoming via the
  working app's binary). Scoped strictly to the 5/MG path — **WHOOP 4.0 buzz is byte-for-byte
  unchanged** (still 79 via its own frame). The strap log now annotates the write `(puffin cmd=0x13)`.
- This may or may not buzz yet (payload unconfirmed); the immediate goal is to confirm the strap now
  **accepts** the command (result `0x01` / a haptics-fired event) instead of rejecting it. 5/MG owners:
  please share a strap log on #48.

## 1.33 — Smart alarm time actually reaches the strap

- **Fixed: the Smart-alarm wake time you set didn't always transmit to the strap** (issue #59). The
  strap's firmware alarm is set over BLE, and the send is gated on bond — but `applySmartAlarm()` was
  only called from the enable/time-change setters (`setSmartAlarm…` / `AutomationsView.onChange`),
  **never on (re)connect**. So a time changed while the strap wasn't bonded was silently dropped, and
  the strap kept its previous time (set 07:15 → still fired at the old 07:00). Both platforms had this
  gap.
- **Fix:** re-arm on the bond `false→true` transition. macOS adds a `live.$bonded.removeDuplicates()`
  sink in `AppModel.init`; Android tracks the bonded transition in `AppViewModel`'s `ble.state`
  collector. Both gated on `smartAlarmEnabled` so a disabled alarm doesn't disarm on every reconnect.
  Net effect: every time the strap reconnects, the current wake time is re-sent — so the time you set
  is the time that fires. (Re-arming on each reconnect also refreshes the next-occurrence epoch.)
- WHOOP 5/MG note unchanged: `armStrapAlarm` is still dropped by `send()` on 5/MG (its command set
  isn't verified) — this fix is for the WHOOP 4.0 firmware alarm, same as before.

## 1.32 — Today trends stay within their window (Mac)

- **Fixed (Mac): Today metric sparklines could draw all-history data under a "14-day trend" label**
  (PR #49, by rr-allin). `sparkValues` fell back to the entire series when the trailing window had
  <2 points, so a stale import rendered months-old points as a current trend. It now returns only
  `trailingWindow(all, days:).map(\.value)` — strictly within the window. A consequence (intended):
  `latestString` reads `.last` of this windowed series, so a metric whose latest reading predates the
  window shows "—" instead of a stale value — same anti-stale spirit as the #23 trailing-window fix,
  and weight's generous 90-day window keeps genuinely-recent-but-sparse readings rendering. The
  `Sparkline` view already handles 0/1 points (empty / single head dot), so no fallback is needed.
- Android: **already correct** — `remember14` strictly filters to the trailing calendar window with no
  all-history fallback (handled in the #23 era), so this is a Mac-only fix + lockstep version bump.

## 1.31 — No HR spike on resume

- **Fixed: heart rate briefly showed a stale ~100 bpm when you reopened the app / returned to Live,
  then drifted down** (issue #46). The hero number is the **median of a short smoothing window**
  (macOS `AppModel.hrWindow`, a 10s/40-sample buffer; Android `AppViewModel.hrWindow`, a 5-sample
  deque). The window was only ever cleared on explicit disconnect — never on resume or BLE re-attach.
  Since the strap only notifies every ~30s, on reopen the window still held the pre-gap samples (from
  when the user's real HR was higher) and republished that stale median until fresh low samples
  refilled it. The strap itself was never wrong (the #46 log never exceeds 75 bpm — the spike was
  entirely in the display layer).
- **Fix:** added a `resetSmoothing()` (clears the window, blanks `bpm` → `—`) and call it from the
  resume hook on each platform — `AppModel.startRealtimeHR()` / `AppViewModel.requestRealtimeHr()`.
  These fire on Live/Health screen entry, **not** on the 30s keep-alive re-arm (which goes straight to
  `ble.startRealtime()`), so steady-state smoothing is untouched; the hero shows `—` only for the brief
  moment until the first fresh reading lands, then shows the truthful value. Mirrors the existing
  `disconnect()` clear. Verified every `bpm` reader is nil-safe (zone coaching, breathe, menu bar).
- Both platforms get the real fix (the bug was present on each; only the recovery time differed).

## 1.30 — Workouts: correct source pill for Health Connect (Android)

- **Fixed (Android): Health Connect workouts showed an "Apple" pill in the Workouts list's Src
  column** (issue #53, follow-up — the Today page was fixed in 1.28). The `SessionRow` badge was a
  binary `isWhoop ? "Whoop" : "Apple"`, so every non-WHOOP session (including `health-connect`) fell
  through to "Apple". It now classifies on the row's stored origin — `deviceId`/`source` of
  `my-whoop` → "Whoop" (accent), `apple-health`/"Apple Health" → "Apple" (cyan),
  `health-connect` → **"HC"** (purple, matching the Data Sources / Today tint). "HC" is abbreviated
  to fit the narrow column, exactly as "Apple" stands in for "Apple Health" there. The classification
  is a pure `workoutSourceLabel()` helper with a unit test pinning all three importer origins.
- macOS: lockstep version bump only — Health Connect is Android-only, so macOS workouts are only ever
  WHOOP or Apple and the existing badge is already correct there.

## 1.29 — Re-scan actually scans on Android

- **Fixed (Android): Re-scan / Connect could silently do nothing on Android 12+** (issue #1; community
  PRs #54/#55). A BLE scan needs the runtime `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT` (Nearby devices)
  permission; the Settings **Re-scan** button called `vm.connect()` directly, so if the permission was
  denied or revoked the scan threw `SecurityException`, the BLE layer swallowed it into a status note,
  and no prompt was ever raised — the button did nothing (the Pixel 9 report). Live's Connect and the
  onboarding flow already gated correctly; Settings was the overlooked path. The permission gate is now
  a single shared Compose helper, `rememberRequestScan {}` (`ui/BlePermissions.kt`), used by both Live
  and Settings, so no entry point can forget it. The gate must stay in the Compose layer — the
  ViewModel can't raise an Activity-scoped prompt.
- **Feedback while searching.** Settings now shows a "Searching…" status detail and disables Re-scan
  while a scan is in flight (`enabled = !live.scanning`); Live's Connect shows "Searching…" and disables
  too. The `scanning`/`statusNote` state already existed and was fully wired in `WhoopBleClient` (set on
  scan start, cleared on every terminal path — timeout, found, connected, disconnect, permission error),
  so no BLE/state changes were needed; only the buttons were missing the `enabled` gate.
- **Live control buttons stay on one line** on narrow phones (`captionNumber` + `maxLines = 1`), which
  also keeps the new longer "Searching…" label from wrapping the row.
- macOS: lockstep version bump only — CoreBluetooth has no Android-style runtime-permission prompt, so
  there's no analogous fix to make (the macOS scanning-feedback parity gap is tracked separately).

## 1.28 — Health Connect: correct source label + workout types (Android)

- **Fixed (Android): Health Connect data showed under the "Apple Health" pill on Today** (issue #53,
  follow-up to #34). The Today provenance footer unioned `apple-health` + `health-connect` into one
  "Apple Health" row. It now keeps them separate — a dedicated **Health Connect** row (its own counts +
  tint) alongside Apple Health — matching the Data Sources screen. `TodayFooterState` gained
  `hcDays`/`hcWorkouts`; the construction splits the two sources; the recent-workouts feed still unions all.

- **Fixed (Android): Health Connect workout types were mislabelled** (issue #53) — e.g. a **walking**
  session showed as **swimming**. The `EXERCISE_TYPE_NAMES` map had **wrong hardcoded integers**: `79`
  was mapped to "Swimming" but `79` is actually `WALKING`; `80` ("Swimming") is `WATER_POLO`; `82`
  ("Walking") is `WHEELCHAIR`; and yoga/HIIT/boxing/hiking/weightlifting were wrong too. The map now
  references `ExerciseSessionRecord.EXERCISE_TYPE_*` **constants** directly, so the int↔label mapping is
  resolved by the library and a renamed/removed constant is a compile error rather than a silent
  mismatch. New imports are correct immediately; **re-import Health Connect data to relabel** sessions
  imported before this fix (the sport name is stored at import time).

## 1.27 — Wrist alerts work on Android

- **Fixed (Android): wrist alerts couldn't be enabled — NOOP didn't appear in Notification Access**
  (issue #52). The Notifications screen had the full wrist-alerts UI (master toggle, per-app filters,
  quiet hours — all already persisted in `NotifPrefs`) and an "Open Notification Access" button, but the
  manifest declared **no `NotificationListenerService`**, so NOOP could never appear in the system's
  Notification Access list (and nothing acted on notifications even if it could). Added
  `com.noop.notif.NoopNotificationListener` + its manifest `<service>` (guarded by
  `BIND_NOTIFICATION_LISTENER_SERVICE`). Once the user grants access and enables wrist alerts, it buzzes
  the strap via the existing `RUN_HAPTICS_PATTERN` path on a posted notification, gated by the persisted
  settings (master, per-app opt-in, the app's buzz pattern → loops, quiet hours with midnight-wrap,
  only-when-worn) and skipping ongoing / foreground-service / group-summary noise. **Privacy-preserving by
  design: it reads only the posting package name — never notification content — and nothing leaves the
  device** (documented in `PRIVACY_SECURITY.md` §2.5). Works on WHOOP 4.0; 5/MG haptics are dropped by the
  `send()` guard until verified (#48).

## 1.26 — Smart alarm actually works on Android

- **Fixed (Android): the Automations "Smart alarm" was a non-functional mock-up** (issue #51). The whole
  screen's toggles were ephemeral `remember { mutableStateOf(false) }` with no persistence and no backend,
  and the wake time was hardcoded static `Text("07:00")` (not tappable) — so the toggle reset on navigation
  and the time couldn't be changed. The smart alarm is now a **real, persisted feature** mirroring macOS:
  `NoopPrefs` stores `smartAlarmEnabled` + `smartAlarmMinutes`; the time uses the reusable `TimeChip`
  picker (now `internal`, shared with the quiet-hours chip); and `AppViewModel.applySmartAlarm()` arms the
  strap's **firmware alarm** via `WhoopBleClient.armStrapAlarm()` (`SET_CLOCK` → `SET_ALARM_TIME(66)` with
  `[0x01]+u32 LE epoch+[0,0]`) / `disableStrapAlarm()` (`DISABLE_ALARM(69)`) — so on **WHOOP 4.0** it buzzes
  at the wake time even if the phone is asleep or NOOP is closed. Needs the strap connected to arm. (On
  5.0/MG the alarm command is dropped by the `send()` guard, same as the buzz, until verified.) The other
  Automations toggles (zone coaching / stress nudge / auto-lock) remain preview-only — a separate follow-up.

## 1.25 — WHOOP 5/MG history offload (experimental) + pairing clarity (Mac)

- **Added (macOS, experimental): a bonded WHOOP 5/MG strap now runs the historical offload.** Four
  interlocking gaps blocked it; all are now fixed, scoped strictly to `.whoop5` (WHOOP 4.0 byte-for-byte
  unchanged): (1) `connectHandshakeDone` is set after the 5/MG bond + notify-subscribe, behind a new
  `whoop5SessionStarted` once-guard that mirrors the WHOOP4 ack-storm guard (so the per-chunk acks
  re-entering `didWriteValueFor` can't re-trigger the offload mid-stream); (2) the whoop5 branch now
  kicks `requestSync(.connect)` + `startBackfillTimer()` (the trigger lived only in the WHOOP4 block);
  (3) `send()` allowlists `SEND_HISTORICAL_DATA` + `HISTORICAL_DATA_RESULT` for 5/MG (puffin-framed,
  same transport as the proven HR toggle); (4) `isOffloadFrame` is family-aware (reads the type byte at
  `frame[8]` for puffin, not `frame[4]`) and inbound puffin offload frames (47/48/49/50) route to the
  Backfiller during a backfill, while live REALTIME_DATA still only reaches the live router; the
  `Backfiller` is family-aware (parse + `end_data` slice `frame[21:29]` for 5/MG, family captured at
  `begin()`). The chunk-ack needs no new code — `send()` already owns the puffin framing + seq. **Brand
  new, needs on-hardware verification; observable stage-by-stage in the strap log.** 117 WhoopProtocol
  tests green; macOS builds clean.

- **Changed (macOS): clearer WHOOP 5/MG pairing.** The bond-refused hint ("free the strap from the WHOOP
  app — pairing mode") now shows on the **Live** screen where people connect (it was Settings-only), and
  the README has a prominent *"Pairing a WHOOP 5.0 / MG — read this first"* guide (the one-bond-at-a-time
  constraint, the `Encryption is insufficient` symptom, and the close-app → pairing-mode → connect steps).

## 1.24 — Switch between a WHOOP 4 and a 5.0/MG (Mac + Android)

- **Fixed (macOS + Android): you couldn't switch straps once one was bonded.** The Live screen's strap
  picker was gated on `!bonded` — but `bonded` is **sticky** (it survives a disconnect, meaning "this
  strap is paired"), so after the first successful pairing the picker disappeared for good. A user with
  both a WHOOP 4 and a 5.0/MG was then stuck: the scan kept targeting the first strap's service
  (`61080001` vs `fd4b0001`), so the other strap was never discovered. The picker now shows whenever
  you're **not actively streaming** (`!(connected && bonded)`), and changing the selection calls a new
  `prepareForModelSwitch()` (`BLEManager`/`WhoopBleClient`) that drops the current strap and clears the
  sticky `connected`/`bonded` state, so the newly-picked model bonds fresh. Pick the strap → Scan &
  Connect. macOS builds clean; full Android unit suite green.

## 1.23 — WHOOP 5.0/MG historical decode parity (Android)

- **Added (Android): WHOOP 5.0/MG type-47 v18 historical records now decode on Android** — bringing it to
  parity with the macOS decode shipped in 1.21. New `decodeWhoop5Historical` in `HistoricalStreams.kt`
  reads the WHOOP5-absolute layout (record @8, so `unix@15`/`hr@22`/`rr@24+`/`gravity@45/49/53` — NOT the
  WHOOP4 V24 offsets) plus the per-second fields each gated to a physical range: `skin_temp_raw@73`
  (kept only when /100 ∈ 20–45 °C), `dynamic_acceleration@41` (f32, 0–8 g), `step_motion_counter@57`,
  `motion_wear_quality@63` (0/1/2). `decodeHistorical` routes the WHOOP5 family to it; the offload
  `extractHistoricalStreams` type-dispatch is now family-aware (`frame[8]` for WHOOP5 vs `frame[4]` for
  WHOOP4). Verified by a new `Whoop5HistoricalDecodeTest` against the **same real worn/off-wrist frames**
  the macOS tests use (so both platforms decode identical bytes); full Android unit suite green, macOS
  unaffected (117 tests). Decode layer only — it activates when the 5/MG history offload runs. Fields the
  source report listed but that didn't decode consistently on this firmware (cardiac/sleep-state/perfusion)
  are deliberately omitted; SpO₂ remains impossible offline.

## 1.22 — Battery refresh on WHOOP 5.0/MG (Mac + Android)

- **Fixed (macOS + Android): "Refresh battery" was a no-op on WHOOP 5.0/MG.** `getBattery()` sent the
  WHOOP 4 proprietary `GET_BATTERY_LEVEL` command, which the `send()` guard **drops** for 5/MG (only the
  HR toggle + buzz are puffin-framed) — so a 5/MG strap's battery only updated via passive `0x2A19`
  notifications, never on demand. Both platforms now read the **standard Battery Level characteristic
  (`0x2A19`)** directly: macOS `BLEManager.refreshBattery()` (`readValue` → existing `didUpdateValueFor`
  parse), Android `WhoopBleClient.refreshBattery()` (`readCharacteristic` → a newly-added
  `onCharacteristicRead` callback → `onInbound` → `setBattery`). The char is also read once at discovery
  when readable, so a value appears as soon as you connect. WHOOP 4 keeps its legacy command path too
  (it gets both). Contributed via #47 (macOS); Android mirrored.

## 1.21 — WHOOP 5.0 historical biometrics + PPG channel fix (Mac)

- **Added (macOS): WHOOP 5.0 type-47 v18 records now decode more biometric fields**, each gated to a
  physically-real range and cross-validated against real worn-vs-off-wrist frames (the data is the
  arbiter): **skin temperature@73** (u16/100 °C — ~30.6 °C worn, ~22.5 °C off-wrist, AS6221 thermistor;
  the raw sensor, not WHOOP's cloud-calibrated summary), **dynamic acceleration@41** (f32 g, gated 0–8),
  a **cumulative motion/step counter@57**, and **wrist-contact/motion quality@63** (enum 0/1/2). Fields
  the source report listed but that did **not** decode consistently on this device's firmware
  (cardiac_flags@33, sleep-state@81, perfusion@69/71) are deliberately left in the raw region pending
  more captures — so NOOP never ships a guessed offset. These are building blocks toward on-device 5.0
  sleep/recovery (decode layer only; not yet surfaced in the UI).

- **Fixed (macOS): the WHOOP 5.0 v26 PPG channel index was read from the wrong byte.** A community
  reverse-engineering report (validated against a 22 h overnight corpus) and NOOP's own two real test
  fixtures both show the channel is **`frame[21]` (values 1–26, a time-multiplexed sweep)**, not
  `frame[12]` — the `0x41`/`0x46` that the merged v1.19 decode reported were a high-entropy counter byte
  caught during a short 2-burst capture. Corrected and gated to 1…26 so a wrong offset stores nothing.
  The PPG **waveform** decode (LE i16 @[27:75]) was always correct and is unchanged. This 26-way
  time-multiplex is also why **SpO₂ is not recoverable offline** (it needs simultaneous red+IR; no two
  channels are ever co-sampled). 117 WhoopProtocol tests green.

## 1.20 — Strap log stays off the system log (Android)

- **Changed (Android): the strap connection log is no longer mirrored to logcat by default** (PR #45).
  It was always written to Android's system log via `Log.d` — even in release builds — so a normal user
  emitted the device's BLE control flow to the device-wide log with no way to turn it off. It's now
  **opt-in**: a new **Settings → Strap → "Debug logging"** toggle (default **off**, persisted as
  `NoopPrefs.KEY_DEBUG_LOGGING`) gates the single `Log.d` call, applied to the process-wide BLE client at
  the composition root so the low-level client never depends on the UI/prefs layer. The in-app ring
  buffer still records unconditionally, so **"Share strap log" keeps working for everyone** (the bug-report
  path from #17/#18) — only the adb-visible mirror is gated. Developers flip it on to watch a session over
  `adb logcat -s WhoopBleClient`. No BLE flow, protocol, or storage change; WHOOP 4.0 and 5/MG unaffected.
  Documented in `PRIVACY_SECURITY.md` §2.4 (what the log does/doesn't contain) and `ANDROID.md`.

## 1.19 — Import polish (Mac) + WHOOP 5 optical decode

- **Changed (macOS): import buttons lock while an import runs** (follow-up to #40). While either
  source is writing to the store, both Data Sources buttons disable and only the active source shows a
  spinner — preventing two concurrent imports and keeping the loading state on the correct card. Each
  source already kept its own status line (from 1.18); this serialises the import itself behind a single
  `activeImportSource`.

- **Added: WHOOP 5.0 optical PPG waveform decoded** (#43). The strap's high-rate type-47 **version-26**
  history record — previously a raw region — is now decoded as a **24 Hz optical photoplethysmography
  (PPG) trace**: 24 little-endian i16 ADC samples per second (`unix` u32 LE @15, channel id @12). It was
  identified as optical, not motion, using heart rate as *internal* ground truth — the concatenated
  waveform autocorrelates to the measured HR (lag 14 ≈ 103 bpm vs 101.7 bpm), trough-detection gives a
  ~563 ms inter-beat interval, and the pulse stays HR-locked even when the wrist is still. Raw ADC counts
  are exposed verbatim as `ppg_waveform` (PPG has no absolute unit — no scale is invented). Visible in
  the strap inspector / `whoop-decode`; a building block toward 5.0 recovery and strain. Decoder-only and
  version-keyed, so v18 and unknown versions are unaffected.

## 1.18 — Import fixes (Mac + Android)

- **Fixed (macOS): an Apple Health import overwrote the WHOOP import's status message** in Data Sources
  (issue #40). The two importers shared one `importing`/`importSummary` state, and only the WHOOP card
  rendered the summary — so importing Apple Health flipped both buttons to loading and replaced the WHOOP
  message in the WHOOP section, looking like a data overwrite. The data was always stored under separate
  sources (`my-whoop` vs `apple-health`); split the UI state per source (`whoopImporting`/`appleImporting`
  + per-source summaries) and gave the Apple Health card its own status line.
- **Fixed (Android): one failing Health Connect record type aborted the whole import** (issue #34). All
  the `readAll` calls ran inside a single try/catch, so a device/SDK quirk on any one type (e.g. the
  "count must not be less than 1, currently 0" some Health Connect builds throw) failed the entire
  import. Each type's read is now self-contained — on failure it's logged and skipped, and every other
  type still imports (reads accumulate into shared buckets, so a partial type is simply absent, never
  corrupt).

---

## 1.17 — Sleep from WHOOP 4 on unmapped firmware (Mac)

- **Fixed (macOS): a WHOOP 4 on firmware whose historical record version NOOP hadn't mapped recorded no
  sleep.** Root cause: sleep is staged from the strap's overnight **gravity/motion** stream
  (`SleepStager.detectSleep` requires gravity — empty gravity → 0 sleeps). The WHOOP 4 historical
  (type-47) post-hook **bailed out entirely on any version outside the schema's `{12, 24}`** —
  `guard resolveVersion(...) else { region("unmapped"); return }` decoded nothing (no HR, no R-R, **no
  gravity**). So the offload "completed" (acks + HISTORY_COMPLETE) yet stored no motion, HR got
  backfilled from the realtime stream (which carries none), and `IntelligenceEngine` produced a day with
  HR but zero sleeps. **Fix:** for an unmapped version, fall back to the canonical **v24 DSP layout**
  (firmware overwhelmingly shares it — the schema notes V12 == V24) and accept it **only if it decodes
  to physically-real data** — `|gravity| ≈ 1 g` (the DSP gravity is a unit vector) and a plausible HR. A
  wrong layout yields random f32 gravity nowhere near 1 g, so it's rejected and the record left raw (the
  Backfiller then logs the unmapped version once to the strap log, so we can map it). Mapped versions are
  unchanged. New tests cover accept + reject. Issue #30. *(Android has its own decoder; this is the Mac
  fix for the reporters' platform.)*

---

## 1.16 — Health Connect shows as Health Connect (Android)

- **Fixed (Android): Health Connect data was attributed to "Apple Health."** `HealthConnectImporter`
  stored its daily aggregates (steps/HR/HRV/sleep/weight) under the shared `apple-health` deviceId — the
  same bucket the Apple Health export uses — so the Data Sources screen counted them under the Apple
  Health card (only the workouts were correctly tagged `health-connect`). It now files **all** Health
  Connect data under its own `health-connect` source, named "Health Connect," and the Data Sources
  Health Connect card shows its own counts. The unified-external-health read sites (Today footer,
  Workouts) union both sources, so nothing disappears; `CompareScreen` is unaffected (Health Connect
  writes no `metricSeries`). A one-time refile runs at the start of a Health Connect import to move any
  legacy `apple-health` Health-Connect data across (safe + idempotent: HC writes no `metricSeries`, so
  `apple-health` daily rows with no `metricSeries` are unambiguously HC-origin; runs before the import so
  re-importing never duplicates). No data was ever lost — labelling only (issue #34).

---

## 1.15 — WHOOP 5/MG: the wrist buzz works

- **The haptic buzz now fires on WHOOP 5.0/MG (experimental), both platforms.** @jamartif confirming live
  HR on v1.13 proved a 5/MG strap acts on NOOP's puffin-framed commands — so the buzz
  (`RUN_HAPTICS_PATTERN`) is now allowlisted through the same `puffinCommandFrame` transport that the
  realtime-HR toggle uses, in `send()` on both `BLEManager.swift` and `WhoopBleClient.kt`. That powers
  Test buzz, the smart alarm, and any haptic feedback on 5/MG. Still experimental — whether the strap
  honours that specific command is the unverified part, but the transport is proven and the worst case is
  a no-op (no link teardown observed with the HR toggle). All other commands stay dropped for 5/MG (the
  offload set needs its own verified framing). Battery already worked on 5/MG via the standard `0x2A19`
  profile, so it needed nothing here. WHOOP 4.0 is unaffected (issue #28).

---

## 1.14 — Android Today: clearer empty states for stale imports

- **Android Today now renders missing current-day metrics as explicit "No Data" instead of raw dashes**,
  and the recovery ring no longer shows a `0% / depleted` state when there's simply no recovery row for
  today — so after a historical import, Today reads as "no score for today yet," not a broken-looking zero.
  Added a Mac-style Today footer for provenance: recent 14-day workouts (when present) plus Data Sources
  counts, so imported history is clearly labelled as history. No change for a user who has today's data —
  values render normally; only genuinely-absent values show "No Data." Brings Android to parity with the
  Mac Today screen and completes the stale-import work from v1.11/v1.12. Android-only (TodayScreen,
  TrendsScreen comment); reimplemented as NOOP from @Brechard's PR #31 (refs #23).

---

## 1.13 — WHOOP 5/MG heart rate on Android

- **Fixed (Android, WHOOP 5/MG): bonded but no heart rate.** Android brought the strap to "Bonded —
  Streaming" (v1.10) but then listened for HR only on the standard `0x2A37` profile — which a 5/MG
  strap doesn't stream. Realtime HR rides the puffin notify chars (`fd4b0003/4/5/7`) as `REALTIME_DATA`,
  exactly as on macOS. NOOP now, on the `.whoop5` path only: (1) subscribes those puffin notify chars
  **after** the `CLIENT_HELLO` bond (they're rejected on an unauthenticated link); (2) makes the frame
  reassembler **family-aware** (5/MG framing is `declLen @[2..4]` / total `+8`, vs WHOOP4 `length @[1..3]`
  / `+4` — the WHOOP4 rule decoded a bogus ~6 KB length and never emitted a frame); (3) decodes `REALTIME_DATA`
  at the WHOOP5 `+4` offsets (HR @16) — the same hardware-verified decode shipped for macOS in PR #21; and
  (4) sends the realtime-HR toggle with **puffin command framing** (`send()` dropped every 5/MG command
  before). Verified by unit tests against a real worn-strap frame (HR=98, R-R=[603,587]); the new decode +
  reassembler are covered. Still experimental on 5/MG; WHOOP 4.0 is byte-for-byte unaffected (issue #17/#26).
- **Note:** other 5/MG commands (battery poll, haptic buzz) still need their own verified puffin framing
  and remain dropped for now — only the realtime-HR toggle is wired, because it's the one confirmed on
  hardware. So buzz on a 5/MG strap isn't expected to fire yet (issue #28).

---

## 1.12 — WHOOP 5/MG heart rate on Mac + Readiness anchoring

- **Fixed (macOS, WHOOP 5/MG): the connect bonding and actually streaming live HR.** The v1.5 attempt
  bonded but still failed on real 5/MG hardware because it subscribed the protected puffin notify chars
  (`fd4b0003/4/5/7`) at *discovery*, before the link was encrypted — the strap rejected them with
  *"Authentication is insufficient"* and the bond write itself failed *"Encryption is insufficient."*
  NOOP now (1) retains those chars but defers the subscribe until the `CLIENT_HELLO` `.withResponse`
  write confirms in `didWriteValueFor`; (2) arms realtime HR post-bond with **puffin command framing**
  (`puffinCommandFrame(TOGGLE_REALTIME_HR)`) — the `send()` guard previously dropped every 5/MG command,
  so even a bonded strap never started streaming; and (3) surfaces actionable pairing-mode guidance when
  the bond is refused (`Encryption/Authentication is insufficient`) — CoreBluetooth won't start a fresh
  just-works bond against a strap still bonded to the official WHOOP app, so it must be in pairing mode
  (blue LEDs, WHOOP app closed). Reimplemented from a 5/MG owner's hardware-verified flow (issue #17).
  WHOOP 4.0 is untouched; the change is scoped entirely to the `.whoop5` path.
- **Fixed (Mac + Android): the Readiness card still anchoring to the newest stored row.** v1.11 anchored
  Today, the sparklines and the Trends windows to the device's real calendar day, but left
  `ReadinessEngine` reading `sorted.last`, so the "Should you push today?" card still synthesised off a
  stale import's newest day. Both platforms now pass the local day key into `evaluate(...)`, and the
  engine treats an explicit-but-absent `today` as *insufficient* rather than falling back to the newest
  row — so on a stale import the readiness card hides instead of showing an old day's read. No-op for
  anyone wearing the strap nightly (today's row exists). Caught via @Brechard's PR #24 (issue #23/#24).

---

## 1.11 — Today reflects today, not stale imports

- **Fixed (Mac + Android): the dashboard treated the newest *imported* day as "today."** After a
  historical WHOOP import, the Today hero, the 14-day sparklines and the Trends W/M/3M windows were all
  anchored to the newest stored *row* (or `latestDay`) rather than the device's actual calendar date —
  so a months-old import showed as today's recovery/readiness, and the trend windows showed the last N
  imported days instead of the last N calendar days. Today now resolves by the real local day key
  (`yyyy-MM-dd`), and the sparkline/Trends windows are date-anchored to today; older imports stay
  visible under the wider ranges / All history. No change for the common case (recent contiguous data:
  last-N-days == last-N-rows) — only stale-import dashboards are corrected (issue #23).

---

## 1.10 — WHOOP 5/MG bonding on Android + Health Monitor fix

- **Fixed (Android, WHOOP 5/MG): the strap connecting but never bonding.** It wrote `CLIENT_HELLO`
  unacknowledged (`WRITE_TYPE_NO_RESPONSE`), which never triggered the just-works bond the `fd4b` strap
  needs — so it sat connected, unbonded, and silent (the strap won't even stream the standard `0x2A37`
  HR on an unauthenticated link). `CLIENT_HELLO` is now a confirmed write that triggers bonding (the
  same fix shipped for macOS in v1.5), so live HR can come through. Experimental; isolated to the 5/MG
  path — WHOOP 4.0 unaffected (issue #17).
- **Fixed (Health Monitor): the heart-rate chart freezing when opened from the Live page.** Leaving
  Live sent `TOGGLE_REALTIME_HR=0`, switching the stream off, so Health Monitor (which also shows live
  HR) got nothing. The realtime stream is now ref-counted and stays on while any live-HR screen is
  visible (issue #18).

---

## 1.9 — Fix: bonded but no live data (Android)

- **Fixed (Android): a strap that connects and bonds but shows no live data** — heart rate, battery,
  worn and events all blank (it reproduces reliably on newer Android). A GATT callback-threading race
  let the bond's with-response write fire before the notification subscriptions and starve them as
  BUSY, so the strap looked bonded (commands like buzz worked) but not one notification was ever
  enabled. NOOP now pins all GATT callbacks to the main looper (API 28+) and retries a transiently-BUSY
  subscribe. Reported, diagnosed and hardware-verified (Pixel 8 / Android 16) by a community
  contributor (PR #22); reviewed for no regression to the verified WHOOP 4.0 path.

---

## 1.8 — Strap-log export on Mac + a Health Monitor fix

- **New (Mac): export the strap log.** The Live screen's strap-log card now has **Copy** and **Save…**
  buttons, so Mac users can attach the connection log to a bug report — Android has had this since 1.6,
  Mac didn't (issue #17).
- **Fixed: Health Monitor heart-rate chart flat-lining.** It derived the chart from R-R intervals,
  which are sparse on WHOOP 4.0, so it sat on a flat 2-point line even while HR was clearly changing.
  It now plots a rolling buffer of your live heart rate over time (issue #18).

---

## 1.7 — WHOOP 5/MG frame capture + protocol workbench

- **New (Mac): opt-in WHOOP 5/MG frame capture.** Settings → Experimental → "Record puffin frames"
  logs the strap's raw 5/MG ("puffin") frames — each stamped with a timestamp and your live heart
  rate as ground-truth — to a JSON file, with Export / Reveal actions. Read-only on the strap, off by
  default, and never touches WHOOP 4.0. This is how 5/MG owners can contribute the captures needed to
  decode recovery / strain / sleep.
- **Dev tooling:** a headless Linux capture workbench (`tools/linux-capture/`, Python + bleak) and a
  `whoop-decode` CLI that decodes captures with the same `WhoopProtocol` decoder the apps ship — no
  second decoder to drift. Plus hardware-verified WHOOP 5.0 bonding/session notes in
  `docs/BLE_REVERSE_ENGINEERING.md` that confirm the v1.5 just-works-bond approach.
- Cherry-picked from community PRs #19 and #20 by @j0b-dev — reviewed, build-verified, and
  reimplemented for the repo.

---

## 1.6 — Share strap logs, and a worn-status fix

- **New (Android): Share strap log.** Settings → Strap → **"Share strap log"** writes the connection
  log to a file and opens the share sheet, so you can attach it to a bug report. Android's logs
  weren't reachable without `adb`, which is why connection problems on Android (issues #17, #18) were
  hard to diagnose — now they're one tap away.
- **Fixed (Android): the "Worn" status always reading Off.** The Android default was wrong (`false`);
  it now defaults to worn until the strap reports otherwise, matching the macOS app (issue #18).
- **Mac:** the alarm debug log now prints your **local** wake time instead of UTC. Alarms already
  fired at the correct local time — the log's "+0000" was just `Date`'s default UTC formatting.

---

## 1.5 — WHOOP 5/MG: secure-pairing fix

- **Fixed (experimental): WHOOP 5.0/MG stuck at "Finishing the secure pairing handshake."** The 5/MG
  strap requires an encrypted (bonded) Bluetooth link before it will let the app subscribe to its
  characteristics — it was rejecting them with "Authentication is insufficient," so the handshake
  waited forever and live heart rate never arrived. NOOP now writes the `CLIENT_HELLO` with-response
  to trigger just-works bonding, then subscribes once the link is authenticated. Diagnosed from a
  shared strap log by a contributor on issue #17. **Still experimental on 5/MG** — if you have one,
  please try it and share your strap log so we can keep improving it. WHOOP 4.0 is unaffected.

---

## 1.4 — Live heart rate that doesn't freeze

- **Fixed: live heart rate freezing mid-session.** The WHOOP firmware lets its realtime stream lapse
  if it isn't periodically re-armed, which left heart rate stuck on a stale number while the strap was
  still "connected" — the only fix was a manual disconnect/reconnect. NOOP now runs a 30-second
  keep-alive that re-arms the realtime stream, re-subscribes a dropped notification, and — if nothing
  has arrived for two minutes — reconnects on its own. This ports the macOS app's existing keep-alive
  to Android, so the two platforms behave the same.
- **Fixed: a corrupt Bluetooth packet could wedge the live stream.** The frame reader now rejects an
  impossible frame length and resyncs to the next packet, and starts each connection from a clean
  buffer, so a single bad packet can't freeze the stream until you reconnect.

---

## 1.3 — Stays connected in the background

- **New: keeps your strap connected when the app is closed.** On Android, NOOP runs a quiet ongoing
  foreground-service notification that holds the Bluetooth link open, so your heart rate keeps
  streaming and offloads keep landing even after you swipe the app away. On macOS this already came
  for free — close the window and NOOP keeps running from the menu bar.
- **New: "Keep connected in the background" toggle** in Settings → Strap, on by default. Turn it off
  and NOOP disconnects whenever you close the app (and drops the notification with it).
- **Fixed:** the strap dropping the instant you closed the app (the connection used to be torn down
  with the screen). The BLE client is now owned by the app process, not the UI.
- **Fixed:** the Android notification permission is now actually declared and requested, so the
  background notification can appear on Android 13+.

---

## 1.2 — Readiness, and the start of WHOOP 5/MG

- **New: Readiness.** A "should you push today?" card on Today that synthesizes established
  sports-science signals from your own history — HRV vs your baseline (Plews/Buchheit), resting-heart-
  rate drift (Lamberts), sleeping respiratory rate, training-load balance (the acute:chronic workload
  ratio, Gabbett) and training variety (monotony, Foster) — into one headline (Primed / Balanced /
  Strained / Run down) with the drivers beneath it. Pure on-device math; not medical advice.
- **WHOOP 5/MG: live heart rate now works.** Deeper 5/MG metrics (recovery, strain, sleep) are still
  experimental and being worked on.
- **Opt-in WHOOP 5/MG protocol probes** under Settings → Experimental, for 5/MG owners who want to
  help map the protocol. Off by default; never affects WHOOP 4.0.
- **Localized exports import fully.** German (and other localized) WHOOP exports now import with real
  values, not blanks — the column headers are mapped, not just the filenames.
- **Fixes.** The WHOOP 5/MG "stuck connecting" state, and the macOS "Choose export" button.

## 1.1 — Scores live from the strap

- **On-device scoring.** Recovery, strain and sleep now compute live from the strap, not only from an
  import. They calibrate over your first few nights, like any recovery wearable.
- **Pick your strap** (WHOOP 4.0 or 5.0/MG) before connecting, so it looks for the right one.
- **Universal macOS build** that runs on both Intel and Apple Silicon.

## 1.0 — First release

- Pair directly with a WHOOP strap over Bluetooth — no WHOOP account, no cloud.
- Compute recovery, strain, HRV and sleep locally on your own device.
- Bring your history: import a WHOOP export, an Apple Health export, or Android Health Connect.
