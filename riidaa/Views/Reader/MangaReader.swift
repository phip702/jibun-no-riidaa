//
//  MangaReader.swift
//  riidaa
//
//  Created by Pierre on 2025/02/17.
//

import SwiftUI
import LazyPager
import Translation

public struct MangaReader: View {
    
    @Environment(\.dismiss) var dismiss
    
    @EnvironmentObject var settings: SettingsModel
    
    @Binding var volume: MangaVolumeModel
    @State var currentPage: Int
    
    @State private var pages: [MangaPageModel] = []
    @State private var currentLine: String? = nil
    
    @State private var translationTrigger: UUID? = nil
    @State private var translationText = ""
    @State private var translatedText = ""
    @State private var showTranslationPopup = false

    @State private var parserOffset: CGFloat = 0
    @GestureState private var dragOffset: CGFloat = 0
    @State private var pageHeight = 0.0
    @State private var ready = false
    
    @State private var orientation = UIDeviceOrientation.landscapeLeft// UIDevice.current.orientation
    
    private var displayedPages: [MangaPageModel] {
        settings.isLTR ? pages : pages.reversed()
    }
    
    
    var isDualPage: Bool {
                UIDevice.current.userInterfaceIdiom == .pad && (UIDevice.current.orientation == .landscapeLeft || UIDevice.current.orientation == .landscapeRight)
//        true
    }
    
    public init(volume: Binding<MangaVolumeModel>, currentPage: Int) {
        self._volume = volume
        self._currentPage = State(initialValue: currentPage)
        if let pages = volume.wrappedValue.pages.array as? [MangaPageModel] {
            self._pages = State(initialValue: pages)
        } else {
            self._pages = State(initialValue: [])
        }
    }
    
    func parserHeight(minHeight: CGFloat, maxHeight: CGFloat) -> CGFloat {
        max(min(minHeight + parserOffset-dragOffset, maxHeight), minHeight)
    }
    
    public var body: some View {
        ZStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .scaleEffect(1.2)
                    Text("\(volume.manga.title)")
                        .frame(maxWidth: UIScreen.main.bounds.width / 3 - 20, alignment: .leading)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.leading, 10)
                Spacer()
                
                SwiftUIWheelPicker(
                    .init(get: {
                        if isDualPage {
                            return settings.isLTR ? currentPage / 2 : (pages.count - 1 - currentPage) / 2
                        } else {
                            return settings.isLTR ? currentPage : pages.count - 1 - currentPage
                        }
                    }, set: {v in
                        if isDualPage {
                            currentPage = settings.isLTR ? v * 2 : max(0, pages.count - 1 - (v * 2))
                        } else {
                            currentPage = settings.isLTR ? v : pages.count - 1 - v
                        }
                    }),
                    items: .constant({
                        if isDualPage {
                            let c = (pages.count + 1) / 2
                            return settings.isLTR ? Array(0..<c) : Array(0..<c).reversed()
                        } else {
                            return settings.isLTR ? Array(0..<pages.count) : Array(0..<pages.count).reversed()
                        }
                    }())
                ) { value in
                    GeometryReader { reader in
                        if isDualPage {
                            let start = value * 2 + 1
                            let tmp: String = (start + 1) < pages.count ? (settings.isLTR ? "\(start)-\(start+1)" : "\(start+1)-\(start)") : "\(start)"
                            Text("\(tmp)")
                                .frame(width: reader.size.width, height: reader.size.height, alignment: .center)
                                .background(start-1 == currentPage ? Color(.systemGray6) : Color.clear)
                                .roundedCorners(10, corners: .allCorners)
                        } else {
                            Text("\(value + 1)")
                                .frame(width: reader.size.width, height: reader.size.height, alignment: .center)
                                .background(value == currentPage ? Color(.systemGray6) : Color.clear)
                                .roundedCorners(10, corners: .allCorners)
                        }
                    }
                }
                .width(.VisibleCount(6))
                .scrollAlpha(0.4)
                .frame(height: 40)
            }
        }
        .onRotate { newRotation in
            orientation = newRotation
            if newRotation == .landscapeLeft || newRotation == .landscapeRight {
                ready = false
                currentPage -= (currentPage%2)
            }
        }
        
        GeometryReader { mainGeom in
            let minHeight = CGFloat(100)//min(mainGeom.size.height * 0.2, max(mainGeom.size.height * 0.1, mainGeom.size.height - pageHeight))
            let maxHeight = mainGeom.size.height * 0.8
            let defaultExpandedOffset = (mainGeom.size.height / 2) - minHeight
            let tHeight1 = (maxHeight + minHeight)/3
            let tHeight2 = 2 * tHeight1
            
            ZStack(alignment: .bottom) {
                Color(UIColor.systemBackground).ignoresSafeArea()
                if isDualPage {
                    // Dual-page iPad layout — unchanged.
                    TabView(selection: .init(get: {
                        currentPage - (currentPage%2)
                    }, set: { v in
                        if ready {
                            currentPage = v - (v%2)
                        }
                    })) {
                        let start = settings.isLTR ? 0 : displayedPages.count % 2
                        ForEach(Array(stride(from: start, to: displayedPages.count, by: 2)), id: \.self) { index in
                            VStack(spacing: 0) {
//                                Text("\(currentPage - (currentPage%2)) \(Int(displayedPages[index].number) - (settings.isLTR ? 1 : 2))")
                                if index + 1 < displayedPages.count {
                                    doublePageDisplay(index1: index, index2: index + 1)
                                } else {
                                    pageDisplay(index: index)
                                }
                            }
                            .zoomable(onInteraction: { if showTranslationPopup { showTranslationPopup = false } })
                            .tag(Int(displayedPages[index].number) - (settings.isLTR ? 1 : 2))
                            .frame(maxHeight: max(100, mainGeom.size.height - minHeight))
                            .offset(y: -minHeight/2)
                            .onAppear {
                                ready = true
                            }
                        }
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                    .transaction { txn in
                        txn.disablesAnimations = true
                    }
                    .onTapGesture {
                        if showTranslationPopup { showTranslationPopup = false }
                        if parserOffset > 0 { parserOffset = 0 }
                    }
                    .onChange(of: currentPage) { newPage in
                        if showTranslationPopup { showTranslationPopup = false }
                        self.currentLine = nil
                        if pages[currentPage].read_at == nil { pages[currentPage].read_at = NSDate() }
                        volume.lastReadPage = Int64(newPage)
                        DispatchQueue.main.async { CoreDataManager.shared.saveContext() }
                    }
                    .onChange(of: currentLine) { _ in
                        if showTranslationPopup { showTranslationPopup = false }
                    }
                } else {
                    // Single-page layout — UIKit-backed interaction layer.
                    // Fills the full ZStack (same as the old TabView did).
                    // bottomInset tells UIKit to keep the image above the parser sheet.
                    MangaReaderContainerView(
                        pages: displayedPages,
                        currentPage: $currentPage,
                        isLTR: settings.isLTR,
                        onLineTapped: { line in currentLine = line },
                        onLineTranslate: { text in
                            translationText = text
                            translationTrigger = UUID()
                        },
                        onInteraction: { if showTranslationPopup { showTranslationPopup = false } },
                        onBackgroundTap: {
                            if showTranslationPopup { showTranslationPopup = false }
                            if parserOffset > 0 { parserOffset = 0 }
                        },
                        showBoxBackground: settings.backgroundColorEnabled,
                        boxBackgroundColor: UIColor(settings.backgroundColor.wrappedValue),
                        showBoxBorder: settings.borderColorEnabled,
                        boxBorderColor: UIColor(settings.borderColor.wrappedValue),
                        boxBorderWidth: CGFloat(settings.borderSize),
                        boxPadding: CGFloat(settings.padding),
                        bottomInset: minHeight
                    )
                    .onChange(of: currentPage) { newPage in
                        if showTranslationPopup { showTranslationPopup = false }
                        self.currentLine = nil
                        if pages[currentPage].read_at == nil { pages[currentPage].read_at = NSDate() }
                        volume.lastReadPage = Int64(newPage)
                        DispatchQueue.main.async { CoreDataManager.shared.saveContext() }
                    }
                    .onChange(of: currentLine) { _ in
                        if showTranslationPopup { showTranslationPopup = false }
                    }
                }
                
                VStack(alignment: .center, spacing: 0) {
                    Capsule()
                        .frame(width: 50, height: 6)
                        .foregroundColor(.gray)
                        .padding(.top, 5)
                        .padding(.bottom, 5)
                    
                    MangaReaderParserView(line: currentLine ?? "", onWordSelected: {
                        if parserOffset < defaultExpandedOffset {
                            parserOffset = defaultExpandedOffset
                        }
                    })
                        .frame(maxWidth: .infinity)
                }
                .frame(height: parserHeight(minHeight: minHeight, maxHeight: maxHeight), alignment: .bottom)
                .background(Color(.systemGray6))
                .roundedCorners(20, corners: [.topLeft, .topRight])
                .gesture(
                    DragGesture(coordinateSpace: .global)
                        .updating($dragOffset) { value, state, tr in
                            state = value.translation.height
                        }
                        .onEnded { value in
                            if minHeight + parserOffset-value.translation.height > tHeight2 {
                                parserOffset = maxHeight - minHeight
                            } else if minHeight + parserOffset-value.translation.height < tHeight1 || value.translation.height > 0 {
                                parserOffset = 0
                            } else {
                                parserOffset = maxHeight - minHeight
                            }
                        }
                )
                .animation(.easeIn(duration: 0.15), value: parserOffset)
            }
        }
        .navigationTitle("\(currentPage + 1)/\(volume.pages.count)")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) {
            TranslationPopupView(
                text: translatedText,
                isVisible: showTranslationPopup,
                maxWidth: UIScreen.main.bounds.width,
                onDismiss: { showTranslationPopup = false }
            )
        }
        .modifier(TranslationTaskModifier(
            trigger: $translationTrigger,
            sourceText: $translationText,
            translatedText: $translatedText,
            showPopup: $showTranslationPopup
        ))
    }
    
    
    @ViewBuilder
    public func pageDisplay(index: Int) -> some View {
        let page = displayedPages[index]
        GeometryReader { geometry in
            let scale = min(geometry.size.width / Double(page.width),
                            geometry.size.height / Double(page.height))
            let offsetY = Double(page.height) * scale / 2
            let offsetX = Double(page.width) * scale / 2
            ZStack(alignment: .center) {
                if abs(index - (settings.isLTR ? self.currentPage : displayedPages.count - self.currentPage)) <= 10
                {
                    if let imageData = page.getImage() {
                        Image(uiImage: imageData)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: "xmark")
                            .resizable()
                            .frame(width: 400)
                        Text("Page \(page.number) failed to load")
                            .frame(maxHeight: .infinity)
                            .background(Color(.systemBackground))
                            .foregroundColor(.primary)
                    }
                } else {
                    Image(systemName: "xmark")
                        .resizable()
                        .scaledToFit()
                }
                MangaReaderBoxes(boxes: page.getBoxes(), scale: scale, offsetX: offsetX, offsetY: offsetY, currentLine: $currentLine, onLongPress: { text in
                    translationText = text
                    translationTrigger = UUID()
                })
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .onAppear {
                pageHeight = Double(page.height) * scale
            }
        }
    }
    
    @ViewBuilder
    public func doublePageDisplay(index1: Int, index2: Int) -> some View {
        let page1 = displayedPages[index1]
        let page2 = displayedPages[index2]
        GeometryReader { geometry in
            let halfWidth = geometry.size.width / 2
            let scale1 = min(halfWidth / Double(page1.width),
                             geometry.size.height / Double(page1.height))
            let scale2 = min(halfWidth / Double(page2.width),
                             geometry.size.height / Double(page2.height))
            
            let offsetY1 = Double(page1.height) * scale1 / 2
            let offsetY2 = Double(page2.height) * scale2 / 2
            
            let offsetX1 = Double(page1.width) * scale1 / 2
            let offsetX2 = Double(page2.width) * scale2 / 2

            ZStack(alignment: .center) {
                if abs(index1 - (settings.isLTR ? self.currentPage : displayedPages.count - self.currentPage)) <= 10
                {
                    HStack(spacing: 0) {
                        if let imageData = page1.getImage() {
                            Image(uiImage: imageData)
                                .resizable()
                                .scaledToFit()
                                .frame(width: halfWidth, alignment: .trailing)
//                                .clipped()
                        } else {
                            Text("Page \(page1.number) failed to load")
                                .frame(maxHeight: .infinity)
                                .background(Color(.systemBackground))
                                .foregroundColor(.primary)
                        }
                        if let imageData = page2.getImage() {
                            Image(uiImage: imageData)
                                .resizable()
                                .scaledToFit()
                                .frame(width: halfWidth, alignment: .leading)
                            //                                .clipped()
                        } else {
                            Text("Page \(page2.number) failed to load")
                                .frame(maxHeight: .infinity)
                                .background(Color(.systemBackground))
                                .foregroundColor(.primary)
                        }
                    }
                } else {
                    Image(systemName: "xmark")
                        .resizable()
                        .scaledToFit()
                }
                MangaReaderBoxes(boxes: page1.getBoxes(), scale: scale1, offsetX: offsetX1, offsetY: offsetY1, currentLine: $currentLine, onLongPress: { text in
                    translationText = text
                    translationTrigger = UUID()
                })
                    .frame(width: halfWidth)
                    .offset(x: -offsetX1)
                MangaReaderBoxes(boxes: page2.getBoxes(), scale: scale2, offsetX: offsetX2, offsetY: offsetY2, currentLine: $currentLine, onLongPress: { text in
                    translationText = text
                    translationTrigger = UUID()
                })
                    .offset(x: offsetX2)
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .onAppear {
                pageHeight = max(Double(page1.height) * scale2, Double(page2.height) * scale2)
            }
        }
    }
    
}


private struct TranslationTaskModifier: ViewModifier {
    @Binding var trigger: UUID?
    @Binding var sourceText: String
    @Binding var translatedText: String
    @Binding var showPopup: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.modifier(TranslationTaskModifierAvailable(
                trigger: $trigger,
                sourceText: $sourceText,
                translatedText: $translatedText,
                showPopup: $showPopup
            ))
        } else {
            content
        }
    }
}

@available(iOS 18.0, *)
private struct TranslationTaskModifierAvailable: ViewModifier {
    @Binding var trigger: UUID?
    @Binding var sourceText: String
    @Binding var translatedText: String
    @Binding var showPopup: Bool
    @State private var config = TranslationSession.Configuration(
        source: Locale.Language(identifier: "ja"),
        target: Locale.Language(identifier: "en")
    )

    func body(content: Content) -> some View {
        content
            .onChange(of: trigger) { _, _ in
                guard !sourceText.isEmpty else { return }
                config.invalidate()
            }
            .translationTask(config) { session in
                guard !sourceText.isEmpty else { return }
                do {
                    let response = try await session.translate(sourceText)
                    translatedText = response.targetText
                    showPopup = true
                } catch {
                    print("Translation error: \(error)")
                }
            }
    }
}

#Preview {
    MangaReader(volume: .init(get: {
        CoreDataManager.sampleManga.volumes[0] as! MangaVolumeModel
    }, set: { _ in }), currentPage: 2)
    .environment(\.managedObjectContext, CoreDataManager.shared.container.viewContext)
    .environmentObject(SettingsModel())
}
