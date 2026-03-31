//
//  TranslationPopupView.swift
//  riidaa
//
//  Created by Pierre on 2025/03/30.
//

import SwiftUI

struct TranslationPopupView: View {
    let text: String
    let isVisible: Bool
    let maxWidth: CGFloat
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(text)
                .font(.body)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                onDismiss?()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.title3)
            }
        }
        .padding(12)
        .frame(maxWidth: maxWidth * 0.8)
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
