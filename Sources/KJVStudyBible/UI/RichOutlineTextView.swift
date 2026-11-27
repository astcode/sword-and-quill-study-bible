import SwiftUI
import UIKit

// MARK: - WYSIWYG Rich Outline Editor Controller (Headings, Bold, Italic, Underline, Bullets, Numbered/Roman Outlines, Checklists, Quotes, Indent)

public enum RichFormatCommand {
    case heading1
    case heading2
    case bodyText
    case bold
    case italic
    case underline
    case bulletList
    case numberedList
    case romanOutline
    case checklist
    case blockQuote
    case indent
    case outdent
    case appendText(String, isQuote: Bool)
}

@MainActor
public final class RichTextEditorController: ObservableObject {
    public weak var textView: UITextView?
    @Published public var isBold: Bool = false
    @Published public var isItalic: Bool = false
    @Published public var isUnderline: Bool = false

    public var baseTextColor: UIColor = UIColor.label

    public static func baseBodyFont(size: CGFloat = 16) -> UIFont {
        UIFont(name: "Georgia", size: size) ?? UIFont.systemFont(ofSize: size)
    }

    public static func makeDefaultAttributes(color: UIColor, size: CGFloat = 16, bold: Bool = false, italic: Bool = false) -> [NSAttributedString.Key: Any] {
        var font = baseBodyFont(size: size)
        var traits: UIFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        if !traits.isEmpty, let desc = font.fontDescriptor.withSymbolicTraits(traits) {
            font = UIFont(descriptor: desc, size: size)
        }
        let pStyle = NSMutableParagraphStyle()
        pStyle.lineSpacing = 4
        pStyle.paragraphSpacing = 4
        return [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: pStyle
        ]
    }

    public func syncActiveStates() {
        guard let tv = textView else { return }
        let attrs: [NSAttributedString.Key: Any]
        if tv.selectedRange.length > 0 && tv.selectedRange.location < tv.textStorage.length {
            attrs = tv.textStorage.attributes(at: tv.selectedRange.location, effectiveRange: nil)
        } else {
            attrs = tv.typingAttributes
        }
        if let font = attrs[.font] as? UIFont {
            let traits = font.fontDescriptor.symbolicTraits
            isBold = traits.contains(.traitBold)
            isItalic = traits.contains(.traitItalic)
        } else {
            isBold = false
            isItalic = false
        }
        let ul = (attrs[.underlineStyle] as? Int) ?? 0
        isUnderline = ul != 0
    }

    public func exportRTF() -> Data? {
        guard let tv = textView, tv.attributedText.length > 0 else { return nil }
        let range = NSRange(location: 0, length: tv.attributedText.length)
        return try? tv.attributedText.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }

    public func apply(_ command: RichFormatCommand) {
        guard let tv = textView else { return }
        switch command {
        case .bold:
            toggleTrait(.traitBold, in: tv)
        case .italic:
            toggleTrait(.traitItalic, in: tv)
        case .underline:
            toggleUnderline(in: tv)
        case .heading1:
            applyLineFont(size: 22, bold: true, italic: false, color: baseTextColor, in: tv)
        case .heading2:
            applyLineFont(size: 18.5, bold: true, italic: false, color: baseTextColor, in: tv)
        case .bodyText:
            applyLineFont(size: 16, bold: false, italic: false, color: baseTextColor, in: tv)
        case .bulletList:
            toggleLinePrefix("• ", in: tv)
        case .numberedList:
            toggleLinePrefix("1. ", in: tv)
        case .romanOutline:
            toggleLinePrefix("I. ", in: tv)
        case .checklist:
            toggleLinePrefix("☐ ", in: tv)
        case .blockQuote:
            applyBlockQuote(in: tv)
        case .indent:
            adjustIndent(delta: 20, in: tv)
        case .outdent:
            adjustIndent(delta: -20, in: tv)
        case .appendText(let text, let isQuote):
            appendFormatted(text, isQuote: isQuote, in: tv)
        }
        tv.delegate?.textViewDidChange?(tv)
        syncActiveStates()
    }

    // MARK: - Formatting Primitives

    private func toggleTrait(_ trait: UIFontDescriptor.SymbolicTraits, in tv: UITextView) {
        let sel = tv.selectedRange
        if sel.length == 0 {
            var attrs = tv.typingAttributes
            let curFont = (attrs[.font] as? UIFont) ?? Self.baseBodyFont()
            attrs[.font] = toggledFont(curFont, trait: trait)
            tv.typingAttributes = attrs
            return
        }
        tv.textStorage.beginEditing()
        tv.textStorage.enumerateAttribute(.font, in: sel) { val, range, _ in
            let cur = (val as? UIFont) ?? Self.baseBodyFont()
            tv.textStorage.addAttribute(.font, value: toggledFont(cur, trait: trait), range: range)
        }
        tv.textStorage.endEditing()
    }

    private func toggledFont(_ font: UIFont, trait: UIFontDescriptor.SymbolicTraits) -> UIFont {
        var traits = font.fontDescriptor.symbolicTraits
        if traits.contains(trait) {
            traits.remove(trait)
        } else {
            traits.insert(trait)
        }
        if let desc = font.fontDescriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: desc, size: font.pointSize)
        }
        return font
    }

    private func toggleUnderline(in tv: UITextView) {
        let sel = tv.selectedRange
        if sel.length == 0 {
            var attrs = tv.typingAttributes
            let cur = (attrs[.underlineStyle] as? Int) ?? 0
            attrs[.underlineStyle] = cur == 0 ? NSUnderlineStyle.single.rawValue : 0
            tv.typingAttributes = attrs
            return
        }
        let cur = (tv.textStorage.attribute(.underlineStyle, at: sel.location, effectiveRange: nil) as? Int) ?? 0
        let next = cur == 0 ? NSUnderlineStyle.single.rawValue : 0
        tv.textStorage.beginEditing()
        tv.textStorage.addAttribute(.underlineStyle, value: next, range: sel)
        tv.textStorage.endEditing()
    }

    private func applyLineFont(size: CGFloat, bold: Bool, italic: Bool, color: UIColor, in tv: UITextView) {
        let nsStr = tv.textStorage.string as NSString
        let lineRange = nsStr.lineRange(for: tv.selectedRange)
        let attrs = Self.makeDefaultAttributes(color: color, size: size, bold: bold, italic: italic)
        if lineRange.length > 0 {
            tv.textStorage.beginEditing()
            tv.textStorage.addAttribute(.font, value: attrs[.font]!, range: lineRange)
            tv.textStorage.addAttribute(.foregroundColor, value: color, range: lineRange)
            tv.textStorage.endEditing()
        }
        tv.typingAttributes = attrs
    }

    private func applyBlockQuote(in tv: UITextView) {
        let nsStr = tv.textStorage.string as NSString
        let lineRange = nsStr.lineRange(for: tv.selectedRange)
        let quoteColor = baseTextColor.withAlphaComponent(0.78)
        let font = Self.makeDefaultAttributes(color: quoteColor, size: 15.5, bold: false, italic: true)[.font]!
        let pStyle = NSMutableParagraphStyle()
        pStyle.lineSpacing = 4
        pStyle.paragraphSpacing = 6
        pStyle.firstLineHeadIndent = 18
        pStyle.headIndent = 18
        if lineRange.length > 0 {
            tv.textStorage.beginEditing()
            tv.textStorage.addAttribute(.font, value: font, range: lineRange)
            tv.textStorage.addAttribute(.foregroundColor, value: quoteColor, range: lineRange)
            tv.textStorage.addAttribute(.paragraphStyle, value: pStyle, range: lineRange)
            tv.textStorage.endEditing()
        }
        tv.typingAttributes = [.font: font, .foregroundColor: quoteColor, .paragraphStyle: pStyle]
    }

    private func adjustIndent(delta: CGFloat, in tv: UITextView) {
        let nsStr = tv.textStorage.string as NSString
        let lineRange = nsStr.lineRange(for: tv.selectedRange)
        let existing = (lineRange.length > 0 && lineRange.location < tv.textStorage.length)
            ? (tv.textStorage.attribute(.paragraphStyle, at: lineRange.location, effectiveRange: nil) as? NSParagraphStyle)
            : (tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle)
        let pStyle = (existing?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        pStyle.lineSpacing = 4
        let nextIndent = max(0, min(120, pStyle.firstLineHeadIndent + delta))
        pStyle.firstLineHeadIndent = nextIndent
        pStyle.headIndent = nextIndent
        if lineRange.length > 0 {
            tv.textStorage.beginEditing()
            tv.textStorage.addAttribute(.paragraphStyle, value: pStyle, range: lineRange)
            tv.textStorage.endEditing()
        }
        tv.typingAttributes[.paragraphStyle] = pStyle
    }

    private func toggleLinePrefix(_ prefix: String, in tv: UITextView) {
        let nsStr = tv.textStorage.string as NSString
        let sel = tv.selectedRange
        let lineRange = nsStr.lineRange(for: sel)
        let lineText = nsStr.substring(with: lineRange)
        let knownPrefixes = ["• ", "☐ ", "☑ ", "1. ", "I. "]
        tv.textStorage.beginEditing()
        if lineText.hasPrefix(prefix) {
            tv.textStorage.replaceCharacters(in: NSRange(location: lineRange.location, length: prefix.utf16.count), with: "")
            tv.textStorage.endEditing()
            tv.selectedRange = NSRange(location: max(lineRange.location, sel.location - prefix.utf16.count), length: 0)
        } else {
            var removeLen = 0
            for kp in knownPrefixes where lineText.hasPrefix(kp) {
                removeLen = kp.utf16.count
                break
            }
            let replaceRange = NSRange(location: lineRange.location, length: removeLen)
            let attrs = tv.typingAttributes.isEmpty ? Self.makeDefaultAttributes(color: baseTextColor) : tv.typingAttributes
            tv.textStorage.replaceCharacters(in: replaceRange, with: NSAttributedString(string: prefix, attributes: attrs))
            tv.textStorage.endEditing()
            tv.selectedRange = NSRange(location: sel.location - removeLen + prefix.utf16.count, length: 0)
        }
    }

    private func appendFormatted(_ text: String, isQuote: Bool, in tv: UITextView) {
        let existing = tv.textStorage.string
        let prefix = (!existing.isEmpty && !existing.hasSuffix("\n")) ? "\n" : ""
        let attrs: [NSAttributedString.Key: Any]
        if isQuote {
            var a = Self.makeDefaultAttributes(color: baseTextColor.withAlphaComponent(0.85), size: 15.5, bold: false, italic: true)
            let p = NSMutableParagraphStyle()
            p.lineSpacing = 4
            p.paragraphSpacing = 6
            p.firstLineHeadIndent = 14
            p.headIndent = 14
            a[.paragraphStyle] = p
            attrs = a
        } else {
            attrs = Self.makeDefaultAttributes(color: baseTextColor)
        }
        tv.textStorage.beginEditing()
        tv.textStorage.append(NSAttributedString(string: prefix + text + "\n", attributes: attrs))
        tv.textStorage.endEditing()
        tv.selectedRange = NSRange(location: tv.textStorage.length, length: 0)
    }
}

// MARK: - Compact WYSIWYG Formatting Bar

public struct RichFormattingToolbar: View {
    @ObservedObject var controller: RichTextEditorController
    let theme: ReadingTheme

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                formatBtn("H1", active: false) { controller.apply(.heading1) }
                formatBtn("H2", active: false) { controller.apply(.heading2) }
                formatBtn("Body", active: false) { controller.apply(.bodyText) }

                Divider().frame(height: 18)

                iconBtn("bold", active: controller.isBold) { controller.apply(.bold) }
                iconBtn("italic", active: controller.isItalic) { controller.apply(.italic) }
                iconBtn("underline", active: controller.isUnderline) { controller.apply(.underline) }

                Divider().frame(height: 18)

                iconBtn("list.bullet", active: false) { controller.apply(.bulletList) }
                iconBtn("list.number", active: false) { controller.apply(.numberedList) }
                formatBtn("I.", active: false) { controller.apply(.romanOutline) }
                iconBtn("checklist", active: false) { controller.apply(.checklist) }
                iconBtn("text.quote", active: false) { controller.apply(.blockQuote) }

                Divider().frame(height: 18)

                iconBtn("increase.indent", active: false) { controller.apply(.indent) }
                iconBtn("decrease.indent", active: false) { controller.apply(.outdent) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .background(theme.panelBackground)
    }

    private func formatBtn(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(active ? .white : theme.primaryText)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(active ? theme.accentBlue : theme.canvasBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.dividerColor, lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }

    private func iconBtn(_ systemName: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? .white : theme.primaryText)
                .frame(width: 28, height: 26)
                .background(active ? theme.accentBlue : theme.canvasBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.dividerColor, lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - UITextView Wrapper with Auto-Continuing Bullets, Numbered & Roman Outlines

public struct RichOutlineTextView: UIViewRepresentable {
    @ObservedObject var controller: RichTextEditorController
    @Binding var plainText: String
    let initialRTF: Data?
    let initialPlainText: String
    let theme: ReadingTheme

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.backgroundColor = .clear
        tv.allowsEditingTextAttributes = true
        tv.isScrollEnabled = true
        tv.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 30, right: 10)
        let textColor = UIColor(theme.primaryText)
        controller.baseTextColor = textColor
        let defaultAttrs = RichTextEditorController.makeDefaultAttributes(color: textColor)
        tv.typingAttributes = defaultAttrs

        if let rtf = initialRTF,
           let loaded = try? NSMutableAttributedString(
               data: rtf,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ) {
            // Ensure text color adapts cleanly to the active reading theme (Paper / Light / Dark)
            loaded.addAttribute(.foregroundColor, value: textColor, range: NSRange(location: 0, length: loaded.length))
            tv.attributedText = loaded
        } else if !initialPlainText.isEmpty {
            tv.attributedText = NSAttributedString(string: initialPlainText, attributes: defaultAttrs)
        } else {
            tv.attributedText = NSAttributedString(string: "", attributes: defaultAttrs)
        }

        controller.textView = tv
        Task { @MainActor in controller.syncActiveStates() }
        return tv
    }

    public func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        let textColor = UIColor(theme.primaryText)
        controller.baseTextColor = textColor
        if controller.textView !== uiView {
            controller.textView = uiView
        }
    }

    public final class Coordinator: NSObject, UITextViewDelegate {
        var parent: RichOutlineTextView

        init(parent: RichOutlineTextView) {
            self.parent = parent
        }

        public func textViewDidChange(_ textView: UITextView) {
            let current = textView.text ?? ""
            if parent.plainText != current {
                parent.plainText = current
            }
            Task { @MainActor in
                self.parent.controller.syncActiveStates()
            }
        }

        public func textViewDidChangeSelection(_ textView: UITextView) {
            Task { @MainActor in
                self.parent.controller.syncActiveStates()
            }
        }

        // Auto-continue bullet points, checklists, numbered lists, and Roman outlines on Return!
        public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard text == "\n", range.length == 0 else { return true }
            let nsStr = textView.textStorage.string as NSString
            let lineRange = nsStr.lineRange(for: NSRange(location: range.location, length: 0))
            let lineText = nsStr.substring(with: lineRange).replacingOccurrences(of: "\n", with: "")

            // Helper to insert continuation prefix or exit empty list item
            func handleList(prefix: String, nextPrefix: String) -> Bool {
                if lineText == prefix || lineText.trimmingCharacters(in: .whitespaces) == prefix.trimmingCharacters(in: .whitespaces) {
                    // Empty bullet/item: clear prefix to exit list cleanly
                    textView.textStorage.beginEditing()
                    textView.textStorage.replaceCharacters(in: NSRange(location: lineRange.location, length: min(prefix.utf16.count, lineRange.length)), with: "")
                    textView.textStorage.endEditing()
                    textView.selectedRange = NSRange(location: lineRange.location, length: 0)
                    textViewDidChange(textView)
                    return false
                }
                let attrs = textView.typingAttributes.isEmpty
                    ? RichTextEditorController.makeDefaultAttributes(color: parent.controller.baseTextColor)
                    : textView.typingAttributes
                let insertStr = "\n" + nextPrefix
                textView.textStorage.beginEditing()
                textView.textStorage.replaceCharacters(in: range, with: NSAttributedString(string: insertStr, attributes: attrs))
                textView.textStorage.endEditing()
                textView.selectedRange = NSRange(location: range.location + insertStr.utf16.count, length: 0)
                textViewDidChange(textView)
                return false
            }

            if lineText.hasPrefix("• ") {
                return handleList(prefix: "• ", nextPrefix: "• ")
            }
            if lineText.hasPrefix("☐ ") || lineText.hasPrefix("☑ ") {
                return handleList(prefix: String(lineText.prefix(2)), nextPrefix: "☐ ")
            }

            // Numbered outline: "1. ", "2. ", ...
            if let dotIdx = lineText.firstIndex(of: "."),
               lineText.index(after: dotIdx) < lineText.endIndex,
               lineText[lineText.index(after: dotIdx)] == " " {
                let numPart = String(lineText[..<dotIdx])
                if let n = Int(numPart), n > 0 && n < 999 {
                    let curPrefix = "\(n). "
                    return handleList(prefix: curPrefix, nextPrefix: "\(n + 1). ")
                }
                let romans = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"]
                if let rIdx = romans.firstIndex(of: numPart), rIdx + 1 < romans.count {
                    return handleList(prefix: "\(numPart). ", nextPrefix: "\(romans[rIdx + 1]). ")
                }
            }
            return true
        }
    }
}
