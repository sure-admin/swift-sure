import SwiftUI

struct MarkdownText: View {
  var source: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
        blockView(block)
      }
    }
  }

  private var blocks: [MarkdownBlock] {
    MarkdownBlock.parse(source)
  }

  @ViewBuilder
  private func blockView(_ block: MarkdownBlock) -> some View {
    switch block {
    case .paragraph(let content):
      inlineText(content)
    case .heading(let level, let content):
      inlineText(content)
        .font(headingFont(level))
        .fontWeight(.semibold)
    case .unorderedItem(let content, let indentation):
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("•")
        inlineText(content)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.leading, CGFloat(indentation) * 16)
    case .orderedItem(let number, let content, let indentation):
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("\(number).")
          .monospacedDigit()
        inlineText(content)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.leading, CGFloat(indentation) * 16)
    case .quote(let content):
      HStack(alignment: .top, spacing: 10) {
        Capsule()
          .fill(.secondary)
          .frame(width: 3)
        inlineText(content)
          .italic()
          .foregroundStyle(.secondary)
      }
    case .code(let content):
      ScrollView(.horizontal) {
        Text(content)
          .font(.system(.callout, design: .monospaced))
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(10)
      }
      .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    case .divider:
      Divider()
    }
  }

  private func inlineText(_ markdown: String) -> Text {
    let options = AttributedString.MarkdownParsingOptions(
      interpretedSyntax: .inlineOnlyPreservingWhitespace
    )
    guard let attributedContent = try? AttributedString(markdown: markdown, options: options) else {
      return Text(markdown)
    }
    return Text(attributedContent)
  }

  private func headingFont(_ level: Int) -> Font {
    switch level {
    case 1: .title2
    case 2: .title3
    default: .headline
    }
  }
}

private enum MarkdownBlock {
  case paragraph(String)
  case heading(level: Int, content: String)
  case unorderedItem(content: String, indentation: Int)
  case orderedItem(number: Int, content: String, indentation: Int)
  case quote(String)
  case code(String)
  case divider

  static func parse(_ source: String) -> [MarkdownBlock] {
    var blocks: [MarkdownBlock] = []
    var paragraphLines: [String] = []
    var codeLines: [String] = []
    var isInsideCodeBlock = false

    func flushParagraph() {
      guard !paragraphLines.isEmpty else { return }
      blocks.append(.paragraph(paragraphLines.joined(separator: " ")))
      paragraphLines.removeAll()
    }

    func flushCode() {
      blocks.append(.code(codeLines.joined(separator: "\n")))
      codeLines.removeAll()
    }

    let lines = source.replacingOccurrences(of: "\r\n", with: "\n")
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map(String.init)

    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      if trimmed.hasPrefix("```") {
        if isInsideCodeBlock {
          flushCode()
        } else {
          flushParagraph()
        }
        isInsideCodeBlock.toggle()
        continue
      }

      if isInsideCodeBlock {
        codeLines.append(line)
        continue
      }

      if trimmed.isEmpty {
        flushParagraph()
        continue
      }

      let headingLevel = min(trimmed.prefix { $0 == "#" }.count, 6)
      if headingLevel > 0 {
        let contentStart = trimmed.index(trimmed.startIndex, offsetBy: headingLevel)
        if contentStart < trimmed.endIndex, trimmed[contentStart].isWhitespace {
          flushParagraph()
          blocks.append(.heading(
            level: headingLevel,
            content: String(trimmed[contentStart...]).trimmingCharacters(in: .whitespaces)
          ))
          continue
        }
      }

      if isDivider(trimmed) {
        flushParagraph()
        blocks.append(.divider)
        continue
      }

      let indentation = line.prefix { $0 == " " || $0 == "\t" }.count / 2
      if let content = unorderedContent(trimmed) {
        flushParagraph()
        blocks.append(.unorderedItem(content: content, indentation: indentation))
        continue
      }

      if let orderedItem = orderedContent(trimmed) {
        flushParagraph()
        blocks.append(.orderedItem(
          number: orderedItem.number,
          content: orderedItem.content,
          indentation: indentation
        ))
        continue
      }

      if trimmed.hasPrefix("> ") {
        flushParagraph()
        blocks.append(.quote(String(trimmed.dropFirst(2))))
        continue
      }

      paragraphLines.append(trimmed)
    }

    if isInsideCodeBlock {
      flushCode()
    } else {
      flushParagraph()
    }
    return blocks
  }

  private static func unorderedContent(_ line: String) -> String? {
    for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
      return String(line.dropFirst(marker.count))
    }
    return nil
  }

  private static func orderedContent(_ line: String) -> (number: Int, content: String)? {
    guard let separator = line.range(of: ". "),
          let number = Int(line[..<separator.lowerBound]) else { return nil }
    return (number, String(line[separator.upperBound...]))
  }

  private static func isDivider(_ line: String) -> Bool {
    let compact = line.filter { !$0.isWhitespace }
    guard compact.count >= 3, let marker = compact.first else { return false }
    return (marker == "-" || marker == "*" || marker == "_") && compact.allSatisfy { $0 == marker }
  }
}
