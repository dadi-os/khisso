import UIKit

/// How many lines a title may take so no word is ever broken mid-word.
enum TitleFit {
    /// `maxLines` while every word of `title` fits on a line `width` points wide at the given type; otherwise 1, where the
    /// title truncates with a tail ellipsis instead of splitting a word.
    static func lines(_ title: String, width: CGFloat, size: CGFloat, weight: UIFont.Weight, maxLines: Int) -> Int {
        guard maxLines > 1 else { return 1 }
        let font = UIFont.systemFont(ofSize: size, weight: weight)
        let widest = title.split(separator: " ").map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return widest <= width ? maxLines : 1
    }
}
