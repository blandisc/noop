import Foundation

// MARK: - Los rótulos del recibo térmico (FER-112)
//
// El recibo se escribió entero en español —el tipo de sesión, los renglones del resumen, la
// coletilla— y así se veía con el teléfono en inglés. Aquí viven traducidos.
//
// OJO con la distinción que hace honesto el arreglo: la CLASIFICACIÓN (¿esta rutina es de
// empuje?) compara contra el nombre que el usuario escribió y por eso se queda en su idioma;
// lo que se traduce es el rótulo que el recibo PINTA. Son dos cosas distintas que antes eran
// la misma cadena.
enum RecipeLabels {
    static var fuerza: String { String(localized: "recibo.tipo.fuerza", defaultValue: "STRENGTH") }
    static var empuje: String { String(localized: "recibo.tipo.empuje", defaultValue: "PUSH") }
    static var tiron: String { String(localized: "recibo.tipo.tiron", defaultValue: "PULL") }
    static var pierna: String { String(localized: "recibo.tipo.pierna", defaultValue: "LEGS") }
}
