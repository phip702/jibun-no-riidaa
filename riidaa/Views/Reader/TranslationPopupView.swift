//
//  TranslationPopupView.swift
//  riidaa
//
//  Created by Pierre on 2025/03/30.
//

import SwiftUI

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct TranslationPopupView: View {
    let text: String
    let isVisible: Bool
    let maxWidth: CGFloat
    var onDismiss: (() -> Void)? = nil

    private let maxLines = 4

    @State private var fullTextHeight: CGFloat = 0
    @State private var maxLinesHeight: CGFloat = 80
    @State private var isAtScrollBottom = false

    private var exceedsMaxLines: Bool {
        fullTextHeight > 0 && fullTextHeight > maxLinesHeight + 1
    }

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Group {
                if exceedsMaxLines {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            Text(text)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id("top")
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(
                                            key: ScrollOffsetKey.self,
                                            value: geo.frame(in: .named("translationScroll")).minY
                                        )
                                    }
                                )
                        }
                        .coordinateSpace(name: "translationScroll")
                        .onPreferenceChange(ScrollOffsetKey.self) { offset in
                            isAtScrollBottom = (-offset + maxLinesHeight) >= fullTextHeight - 1
                        }
                        .onChange(of: text) { _ in
                            DispatchQueue.main.async { proxy.scrollTo("top", anchor: .top) }
                        }
                        .onChange(of: isVisible) { newVal in
                            if newVal { DispatchQueue.main.async { proxy.scrollTo("top", anchor: .top) } }
                        }
                        .scrollIndicators(.visible)
                        .frame(height: maxLinesHeight)
                        .overlay(alignment: .bottom) {
                            if !isAtScrollBottom {
                                LinearGradient(
                                    colors: [.clear, Color(.systemGray6)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .frame(height: 20)
                                .allowsHitTesting(false)
                            }
                        }
                    }
                } else {
                    Text(text)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(
                ZStack {
                    Text(text)
                        .font(.body)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear { fullTextHeight = geo.size.height }
                                    .onChange(of: geo.size.height) { newH in
                                        fullTextHeight = newH
                                    }
                            }
                        )
                    Text(Array(repeating: "W", count: maxLines).joined(separator: "\n"))
                        .font(.body)
                        .hidden()
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear { maxLinesHeight = geo.size.height }
                            }
                        )
                }
            )

            Button {
                onDismiss?()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: maxWidth * 0.9)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .shadow(radius: 4, y: 2)
        .padding(.top, 10)
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
    }
}

#Preview {
    TranslationPopupView(
        text: "This is a sample translation.",
        isVisible: true,
        maxWidth: UIScreen.main.bounds.width
    )
}
