import Foundation

/// LaTeX math in a message as plain Unicode, for the places that show a
/// message as text rather than rendering it: the drawer's previews and the
/// watch. Math is found by the rule the thread renders by (``MathDelimiters``),
/// so "$412 left, $5 and $10" stays money.
enum UnicodeMath {
    /// `source` with each math span replaced by its Unicode reading.
    static func text(_ source: String) -> String {
        MathDelimiters.pieces(source).map { piece in
            switch piece {
            case .text(let text): text
            case .math(let tex, _): expression(tex)
            case .dollar: "$"
            }
        }.joined()
    }

    /// The TeX `latex` (without delimiters) as Unicode: known commands become
    /// their symbols, `\frac{a}{b}` reads a/b, `\sqrt{x}` √x, and `^`/`_` become
    /// superscript and subscript characters where Unicode has them. Unknown
    /// commands stay as written.
    static func expression(_ latex: String) -> String {
        var reader = Reader(rest: latex[...])
        var out = reader.sequence()
        while !reader.rest.isEmpty {
            reader.rest.removeFirst()
            out += reader.sequence()
        }
        return out
    }

    /// Reads TeX left to right, one group at a time.
    private struct Reader {
        var rest: Substring

        /// Everything up to the end or the `}` closing the current group.
        mutating func sequence() -> String {
            var out = ""
            while let next = rest.first, next != "}" {
                out += atom()
            }
            return out
        }

        /// One unit: a command, a `{group}`, a script or a character.
        mutating func atom() -> String {
            guard let next = rest.popFirst() else { return "" }
            switch next {
            case "\\": return command()
            case "{":
                let inner = sequence()
                _ = rest.popFirst()
                return inner
            case "^": return UnicodeMath.script(argument(), map: UnicodeMath.superscripts, marker: "^")
            case "_": return UnicodeMath.script(argument(), map: UnicodeMath.subscripts, marker: "_")
            case "~": return " "
            default: return String(next)
            }
        }

        /// A command's or script's argument: a group, a command or one character.
        mutating func argument() -> String {
            while rest.first == " " { rest.removeFirst() }
            return atom()
        }

        /// The command after a backslash.
        mutating func command() -> String {
            let name = String(rest.prefix(while: \.isLetter))
            guard !name.isEmpty else {
                guard let symbol = rest.popFirst() else { return "\\" }
                switch symbol {
                case ",", ";", ":", " ": return " "
                case "!": return ""
                case "\\": return " "
                default: return String(symbol)
                }
            }
            rest.removeFirst(name.count)
            switch name {
            case "frac", "dfrac", "tfrac":
                let numerator = argument()
                let denominator = argument()
                return UnicodeMath.grouped(numerator) + "/" + UnicodeMath.grouped(denominator)
            case "sqrt":
                if rest.first == "[" {
                    let index = String(rest.dropFirst().prefix { $0 != "]" })
                    rest = rest.dropFirst(index.count + 2)
                    return UnicodeMath.script(index, map: UnicodeMath.superscripts, marker: "") + "√" + UnicodeMath.grouped(argument())
                }
                return "√" + UnicodeMath.grouped(argument())
            case "mathbb":
                return String(argument().map { UnicodeMath.doubleStruck[$0] ?? $0 })
            case "text", "textrm", "textbf", "textit", "mathrm", "mathbf", "mathit", "mathsf", "mathtt", "mathcal", "operatorname", "boldsymbol", "bm":
                return argument()
            case "left", "right", "bigl", "bigr", "Bigl", "Bigr", "big", "Big":
                if rest.first == "." { rest.removeFirst() }
                return ""
            case "displaystyle", "textstyle", "limits", "nolimits":
                return ""
            default:
                return UnicodeMath.symbols[name] ?? "\\" + name
            }
        }
    }

    /// `text` in script characters when every character has one, else marked
    /// with `marker` as plain text, in parentheses when longer than one
    /// character.
    static func script(_ text: String, map: [Character: Character], marker: String) -> String {
        let mapped = text.compactMap { map[$0] }
        if !text.isEmpty, mapped.count == text.count { return String(mapped) }
        return marker + (text.count == 1 ? text : "(" + text + ")")
    }

    /// `text` wrapped in parentheses unless it is a single number or name.
    static func grouped(_ text: String) -> String {
        text.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." } ? text : "(" + text + ")"
    }

    /// TeX command names and the Unicode they read as.
    static let symbols: [String: String] = [
        "rightarrow": "→", "to": "→", "leftarrow": "←", "gets": "←", "leftrightarrow": "↔",
        "Rightarrow": "⇒", "Leftarrow": "⇐", "Leftrightarrow": "⇔", "implies": "⟹", "iff": "⟺",
        "longrightarrow": "⟶", "longleftarrow": "⟵", "mapsto": "↦", "uparrow": "↑", "downarrow": "↓",
        "times": "×", "cdot": "·", "div": "÷", "pm": "±", "mp": "∓", "ast": "∗", "star": "⋆",
        "circ": "∘", "bullet": "•", "oplus": "⊕", "otimes": "⊗",
        "le": "≤", "leq": "≤", "ge": "≥", "geq": "≥", "ne": "≠", "neq": "≠", "approx": "≈",
        "sim": "∼", "simeq": "≃", "cong": "≅", "equiv": "≡", "propto": "∝", "ll": "≪", "gg": "≫",
        "in": "∈", "notin": "∉", "ni": "∋", "subset": "⊂", "subseteq": "⊆", "supset": "⊃", "supseteq": "⊇",
        "cup": "∪", "cap": "∩", "setminus": "∖", "emptyset": "∅", "varnothing": "∅", "mid": "∣",
        "parallel": "∥", "perp": "⊥",
        "forall": "∀", "exists": "∃", "neg": "¬", "lnot": "¬", "land": "∧", "wedge": "∧", "lor": "∨",
        "vee": "∨", "top": "⊤", "bot": "⊥", "therefore": "∴", "because": "∵",
        "sum": "∑", "prod": "∏", "int": "∫", "iint": "∬", "oint": "∮", "partial": "∂", "nabla": "∇",
        "infty": "∞", "angle": "∠", "degree": "°", "prime": "′", "ldots": "…", "dots": "…", "cdots": "⋯",
        "vdots": "⋮", "ddots": "⋱", "hbar": "ℏ", "ell": "ℓ", "Re": "ℜ", "Im": "ℑ", "aleph": "ℵ",
        "langle": "⟨", "rangle": "⟩", "lfloor": "⌊", "rfloor": "⌋", "lceil": "⌈", "rceil": "⌉",
        "vert": "|", "lvert": "|", "rvert": "|", "Vert": "‖", "lbrace": "{", "rbrace": "}",
        "quad": " ", "qquad": "  ",
        "sin": "sin", "cos": "cos", "tan": "tan", "sec": "sec", "csc": "csc", "cot": "cot",
        "arcsin": "arcsin", "arccos": "arccos", "arctan": "arctan", "sinh": "sinh", "cosh": "cosh",
        "tanh": "tanh", "log": "log", "ln": "ln", "exp": "exp", "lim": "lim", "max": "max", "min": "min",
        "det": "det", "gcd": "gcd", "mod": "mod", "bmod": "mod",
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε", "varepsilon": "ε",
        "zeta": "ζ", "eta": "η", "theta": "θ", "vartheta": "ϑ", "iota": "ι", "kappa": "κ",
        "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "omicron": "ο", "pi": "π", "varpi": "ϖ",
        "rho": "ρ", "varrho": "ϱ", "sigma": "σ", "varsigma": "ς", "tau": "τ", "upsilon": "υ",
        "phi": "φ", "varphi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω",
        "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ", "Pi": "Π", "Sigma": "Σ",
        "Upsilon": "Υ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
    ]

    /// Characters Unicode has a superscript form of.
    static let superscripts: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "−": "⁻", "=": "⁼", "(": "⁽", ")": "⁾",
        "a": "ᵃ", "b": "ᵇ", "c": "ᶜ", "d": "ᵈ", "e": "ᵉ", "f": "ᶠ", "g": "ᵍ", "h": "ʰ", "i": "ⁱ",
        "j": "ʲ", "k": "ᵏ", "l": "ˡ", "m": "ᵐ", "n": "ⁿ", "o": "ᵒ", "p": "ᵖ", "r": "ʳ", "s": "ˢ",
        "t": "ᵗ", "u": "ᵘ", "v": "ᵛ", "w": "ʷ", "x": "ˣ", "y": "ʸ", "z": "ᶻ",
        "T": "ᵀ", "′": "′", "∘": "°", "*": "*",
    ]

    /// Characters Unicode has a subscript form of.
    static let subscripts: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "-": "₋", "−": "₋", "=": "₌", "(": "₍", ")": "₎",
        "a": "ₐ", "e": "ₑ", "h": "ₕ", "i": "ᵢ", "j": "ⱼ", "k": "ₖ", "l": "ₗ", "m": "ₘ", "n": "ₙ",
        "o": "ₒ", "p": "ₚ", "r": "ᵣ", "s": "ₛ", "t": "ₜ", "u": "ᵤ", "v": "ᵥ", "x": "ₓ",
        "β": "ᵦ", "γ": "ᵧ", "ρ": "ᵨ", "φ": "ᵩ", "χ": "ᵪ",
    ]

    /// `\mathbb` letters.
    static let doubleStruck: [Character: Character] = [
        "R": "ℝ", "N": "ℕ", "Z": "ℤ", "Q": "ℚ", "C": "ℂ", "P": "ℙ", "H": "ℍ",
    ]
}
