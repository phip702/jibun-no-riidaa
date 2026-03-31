//
//  MangaReaderParserView.swift
//  riidaa
//
//  Created by Pierre on 2025/03/27.
//

import SwiftUI

struct MangaReaderParserView: View {
    
    let line: String
    var onWordSelected: (() -> Void)? = nil
    @State var parsedText: [ParsingResult] = []
    @State var selectedElement: Int?
    @State var loading = false
    
    @State private var inflectionDescription: InflectionDescription? //= InflectionRule.continuative.description
    @State private var showCopied: Bool = false
    @State private var copiedText: String = ""
    
    
    @EnvironmentObject var settings: SettingsModel
    
    var body: some View {
        ZStack {
            if let description = inflectionDescription {
                VStack(alignment: .leading) {
                    Button {
                        inflectionDescription = nil
                    } label: {
                        HStack {
                            Image(systemName: "chevron.left")
                                .scaledToFit()
                            Text("Back")
                        }
                    }
                    .padding()
                    ParserDefinition(desc: description)
                }
                .transition(.move(edge: .trailing))
            } else {
                ZStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        if loading {
                            ProgressView()
                        } else if line == "" && self.parsedText.isEmpty {
                            Spacer()
                            Text("Select a text box")
                                .font(.title2)
                                .italic()
                                .foregroundStyle(.secondary)
                            Spacer()
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 0) {
                                    Button("Copy") {
                                        let textBox = line.isEmpty ? parsedText.map(\.original).joined() : line
                                        #if canImport(UIKit)
                                        UIPasteboard.general.string = textBox
                                        #else
                                        let pb = NSPasteboard.general
                                        pb.clearContents()
                                        pb.setString(textBox, forType: .string)
                                        #endif
                                        copiedText = "Text Box"
                                        withAnimation {
                                            showCopied = true
                                        }
                                        Task {
                                            try? await Task.sleep(nanoseconds: 1_600_000_000)
                                            withAnimation {
                                                showCopied = false
                                            }
                                        }
                                    }
                                    .padding(.vertical, 7)
                                    .padding(.horizontal, 10)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(7)

                                    ForEach(Array(parsedText.enumerated()), id: \.offset) { index, element in
                                        ParserText(text: element.original)
                                            .font(.largeTitle)
                                            .padding([.horizontal], 4)
                                            .padding([.vertical], 7)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(selectedElement == index ? Color.blue.opacity(0.3) : Color.clear)
                                            .cornerRadius(10)
                                            .onTapGesture {
                                                if selectedElement == index {
                                                    let toCopy = element.original
                                                    #if canImport(UIKit)
                                                    UIPasteboard.general.string = toCopy
                                                    #else
                                                    let pb = NSPasteboard.general
                                                    pb.clearContents()
                                                    pb.setString(toCopy, forType: .string)
                                                    #endif
                                                    copiedText = toCopy
                                                    withAnimation {
                                                        showCopied = true
                                                    }
                                                    Task {
                                                        try? await Task.sleep(nanoseconds: 1_600_000_000)
                                                        withAnimation {
                                                            showCopied = false
                                                        }
                                                    }
                                                } else {
                                                    selectedElement = index
                                                    onWordSelected?()
                                                    print("User clicked parsed text: \(element.original)")
                                                    // Show dictionary form if available and print what we'd store in the DB
                                                    if let firstResult = element.results.first {
                                                        let dictForm = firstResult.term.term
                                                        let reading = firstResult.term.reading
                                                        let now = Date()
                                                        let iso = ISO8601DateFormatter().string(from: now)
                                                        let isSingleKanji: Bool = {
                                                            guard dictForm.count == 1, let scalar = dictForm.unicodeScalars.first else { return false }
                                                            let val = scalar.value
                                                            return (0x4E00...0x9FFF).contains(val) || (0x3400...0x4DBF).contains(val) || (0x20000...0x2A6DF).contains(val)
                                                        }()

                                                        // Single kanji that aren't standalone words should only be tracked
                                                        // as kanji lookups, not word lookups. A standalone word is one that
                                                        // has a non-WaniKani dictionary entry with a positive score.
                                                        let isStandaloneWord: Bool = !isSingleKanji || element.results.contains { r in
                                                            !r.term.dictionary.title.lowercased().contains("wanikani") && r.term.score > 0
                                                        }

                                                        // Debug: object to be inserted into `lookup_events`
                                                        let readingDesc = reading.isEmpty ? "nil" : reading
                                                        print("lookupEvent DB ENTRY: {dictionaryForm: \"\(dictForm)\", reading: \"\(readingDesc)\", date: \"\(iso)\", isStandaloneWord: \(isStandaloneWord)}")

                                                        // Persist lookup event and kanji lookups atomically using one timestamp
                                                        if let db = SQLiteManager.shared.getDatabase() {
                                                            do {
                                                                try db.transaction {
                                                                    if isStandaloneWord {
                                                                        try SQLiteManager.shared.insertLookupEventThrowing(dictionaryForm: dictForm, reading: reading.isEmpty ? nil : reading, dateISO: iso)
                                                                    }
                                                                    try SQLiteManager.shared.insertKanjiLookupIfKanji(dictForm, date: now)
                                                                }
                                                            } catch {
                                                                print("Lookup transaction error: \(error)")
                                                            }
                                                        } else {
                                                            // Fallback: non-transactional insert
                                                            if isStandaloneWord {
                                                                SQLiteManager.shared.insertLookupEvent(dictionaryForm: dictForm, reading: reading.isEmpty ? nil : reading)
                                                            }
                                                            do {
                                                                try SQLiteManager.shared.insertKanjiLookupIfKanji(dictForm, date: now)
                                                            } catch {
                                                                print("Kanji insert error: \(error)")
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                    }

                                }
                            }
                            if let selectedElement = selectedElement {
                                ScrollView(showsIndicators: false) {
                                    LazyVStack(alignment: .leading) {
                                        ForEach(parsedText[selectedElement].results, id: \.self) { result in
                                            ResultView(result: result, fullSentence: line, definition: $inflectionDescription)
                                        }
                                    }
                                }
                                .padding([.horizontal])
                                .frame(
                                    minWidth: 0,
                                    maxWidth: .infinity,
                                    minHeight: 0,
                                    maxHeight: .infinity,
                                    alignment: .leading
                                )
                            }
                            Spacer()
                        }
                    }

                    if showCopied {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.white)
                            Text("Copied \(copiedText)")
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .bold()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(12)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(1)
                    }
                }
                .padding([.leading, .trailing])
                .onChange(of: line) { newLine in
                    self.selectedElement = nil
                    parsedText = []
                    if newLine != "" {
                        parseLine(line: newLine)
                    }
                }
                .transition(.move(edge: .leading))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: inflectionDescription)
        .onAppear {
            if line != "" {
                parseLine(line: line)
            }
        }
    }
}

extension MangaReaderParserView {
    
    func parseLine(line: String) {
        self.loading = true
        DispatchQueue.global(qos: .userInteractive).async {
            
            var results: [ParsingResult] = []
            
            let punctuations = #"[。．、，゠＝？！（）「」｛｝［］【】…‥〽〝〟　〜：♪＜＞～]+"#
            let regex = try! NSRegularExpression(pattern: punctuations, options: [])
            
            var lastIndex = 0
            let nsLine = line as NSString
            
            for match in regex.matches(in: line, options: [], range: NSRange(location: 0, length: nsLine.length)) {
                let range = match.range
                if range.location > lastIndex {
                    let chunk = nsLine.substring(with: NSRange(location: lastIndex, length: range.location - lastIndex))
                    let result = Parser.parse(text: chunk)
                    if !result.isEmpty {
                        results.append(contentsOf: result)
                    } else {
                        results.append(ParsingResult(original: chunk, results: []))
                    }
                }
                let punctuation = nsLine.substring(with: range)
                results.append(ParsingResult(original: punctuation, results: []))
                lastIndex = range.location + range.length
            }
            
            if lastIndex < nsLine.length {
                let chunk = nsLine.substring(from: lastIndex)
                let result = Parser.parse(text: chunk)
                if !result.isEmpty {
                    results.append(contentsOf: result)
                } else {
                    results.append(ParsingResult(original: chunk, results: []))
                }
            }
            
            DispatchQueue.main.async {
                if results.count > 0 {
                    self.parsedText = results
                    self.selectedElement = nil
                }
                self.loading = false
            }
        }
    }
    
}

#Preview {
    MangaReaderParserView(
        line: "",
        //        line: "君は学校を何だと思っているのかね",
        parsedText: [
            ParsingResult(original: "君", results: [
                TermDeinflection(term: TermDB(term: "君", reading: "きみ", definitionTags: [], wordTypes: [], score: 200, definitions: Data(), sequenceNumber: 1, termTags: [], dictionary: DictionaryDB(id: 1, revision: "", title: "", format: 3), exportedToAnki: false), deinflections: [Deinflection(text: "君", inflections: [], types: [])])
            ]),
            ParsingResult(original: "は", results: [
                TermDeinflection(term: TermDB(term: "は", reading: "は", definitionTags: [], wordTypes: [], score: 200, definitions: Data(), sequenceNumber: 1, termTags: [], dictionary: DictionaryDB(id: 1, revision: "", title: "", format: 3), exportedToAnki: false), deinflections: [Deinflection(text: "は", inflections: [], types: [])])
            ]),
            ParsingResult(original: "学校", results: [
                TermDeinflection(term: TermDB(term: "学校", reading: "がっこう", definitionTags: [], wordTypes: [], score: 200, definitions: Data(), sequenceNumber: 1, termTags: [], dictionary: DictionaryDB(id: 1, revision: "", title: "", format: 3), exportedToAnki: false), deinflections: [Deinflection(text: "学校", inflections: [], types: [])])
            ]),
            ParsingResult(original: "を", results: [
                TermDeinflection(term: TermDB(term: "を", reading: "を", definitionTags: [], wordTypes: [], score: 200, definitions: Data(), sequenceNumber: 1, termTags: [], dictionary: DictionaryDB(id: 1, revision: "", title: "", format: 3), exportedToAnki: false), deinflections: [Deinflection(text: "を", inflections: [], types: [])])
            ]),
            ParsingResult(original: "何だと", results: [
                TermDeinflection(term: TermDB(term: "何だと", reading: "なんだと", definitionTags: [], wordTypes: [], score: 200, definitions: Data(), sequenceNumber: 1, termTags: [], dictionary: DictionaryDB(id: 1, revision: "", title: "", format: 3), exportedToAnki: false), deinflections: [Deinflection(text: "何だと", inflections: [], types: [])])
            ]),
            ParsingResult(original: "思っている", results: [
                TermDeinflection(
                    term: TermDB(
                        term: "思う",
                        reading: "おもう",
                        definitionTags: ["★", "priority form"],
                        wordTypes: [],
                        score: 200,
                        definitions:
                            "[{\"type\":\"structured-content\",\"content\":[{\"style\":{\"listStyleType\":\"\\\"＊\\\"\"},\"lang\":\"ja\",\"content\":[{\"tag\":\"li\",\"content\":[{\"data\":{\"code\":\"v5u\"},\"title\":\"Godan verb with 'u' ending\",\"style\":{\"fontSize\":\"0.8em\",\"color\":\"white\",\"cursor\":\"help\",\"borderRadius\":\"0.3em\",\"fontWeight\":\"bold\",\"marginRight\":\"0.25em\",\"padding\":\"0.2em 0.3em\",\"wordBreak\":\"keep-all\",\"verticalAlign\":\"text-bottom\",\"backgroundColor\":\"#565656\"},\"content\":\"5-dan\",\"tag\":\"span\"},{\"data\":{\"code\":\"vt\"},\"title\":\"transitive verb\",\"style\":{\"fontSize\":\"0.8em\",\"color\":\"white\",\"cursor\":\"help\",\"borderRadius\":\"0.3em\",\"fontWeight\":\"bold\",\"marginRight\":\"0.25em\",\"padding\":\"0.2em 0.3em\",\"wordBreak\":\"keep-all\",\"verticalAlign\":\"text-bottom\",\"backgroundColor\":\"#565656\"},\"content\":\"transitive\",\"tag\":\"span\"},{\"tag\":\"ol\",\"content\":[{\"data\":{\"sense-number\":\"1\"},\"style\":{\"paddingLeft\":\"0.25em\",\"listStyleType\":\"\\\"①\\\"\"},\"content\":[{\"tag\":\"ul\",\"data\":{\"content\":\"glossary\"},\"content\":[{\"tag\":\"li\",\"content\":\"to think\"},{\"tag\":\"li\",\"content\":\"to consider\"},{\"tag\":\"li\",\"content\":\"to believe\"},{\"tag\":\"li\",\"content\":\"to reckon\"}]},{\"data\":{\"content\":\"extra-info\"},\"style\":{\"marginLeft\":\"0.5em\"},\"content\":[{\"data\":{\"content\":\"sense-note\"},\"style\":{\"borderRadius\":\"0.4rem\",\"marginTop\":\"0.5rem\",\"borderWidth\":\"calc(3em / var(--font-size-no-units, 14))\",\"borderStyle\":\"none none none solid\",\"borderColor\":\"goldenrod\",\"padding\":\"0.5rem\",\"marginBottom\":\"0.5rem\",\"backgroundColor\":\"color-mix(in srgb, goldenrod 5%, transparent)\"},\"content\":[{\"tag\":\"div\",\"style\":{\"color\":\"#777\",\"fontStyle\":\"italic\",\"fontSize\":\"0.8em\"},\"content\":\"Note\"},{\"tag\":\"div\",\"style\":{\"marginLeft\":\"0.5rem\"},\"content\":\"想う has connotations of heart-felt\"}],\"tag\":\"div\"},{\"tag\":\"div\",\"content\":{\"data\":{\"sentence-key\":\"思う\",\"content\":\"example-sentence\",\"source\":\"143025\",\"source-type\":\"tat\"},\"style\":{\"borderRadius\":\"0.4rem\",\"marginTop\":\"0.5rem\",\"borderWidth\":\"calc(3em / var(--font-size-no-units, 14))\",\"borderStyle\":\"none none none solid\",\"borderColor\":\"var(--text-color, var(--fg, #333))\",\"padding\":\"0.5rem\",\"marginBottom\":\"0.5rem\",\"backgroundColor\":\"color-mix(in srgb, var(--text-color, var(--fg, #333)) 5%, transparent)\"},\"content\":[{\"data\":{\"content\":\"example-sentence-a\"},\"style\":{\"fontSize\":\"1.3em\"},\"content\":[\"晴れだと\",{\"tag\":\"span\",\"style\":{\"color\":\"color-mix(in srgb, lime, var(--text-color, var(--fg, #333)))\"},\"content\":\"思う\"},\"よ。\"],\"tag\":\"div\"},{\"data\":{\"content\":\"example-sentence-b\"},\"style\":{\"fontSize\":\"0.8em\"},\"content\":[\"I think it will be sunny.\",{\"data\":{\"content\":\"attribution-footnote\"},\"style\":{\"marginLeft\":\"0.25rem\",\"color\":\"#777\",\"verticalAlign\":\"top\",\"fontSize\":\"0.8em\"},\"content\":\"[1]\",\"tag\":\"span\"}],\"tag\":\"div\"}],\"tag\":\"div\"}}],\"tag\":\"div\"}],\"tag\":\"li\"},{\"data\":{\"sense-number\":\"2\"},\"style\":{\"paddingLeft\":\"0.25em\",\"listStyleType\":\"\\\"②\\\"\"},\"content\":{\"tag\":\"ul\",\"data\":{\"content\":\"glossary\"},\"content\":[{\"tag\":\"li\",\"content\":\"to think (of doing)\"},{\"tag\":\"li\",\"content\":\"to plan (to do)\"}]},\"tag\":\"li\"},{\"data\":{\"sense-number\":\"3\"},\"style\":{\"paddingLeft\":\"0.25em\",\"listStyleType\":\"\\\"③\\\"\"},\"content\":[{\"tag\":\"ul\",\"data\":{\"content\":\"glossary\"},\"content\":[{\"tag\":\"li\",\"content\":\"to judge\"},{\"tag\":\"li\",\"content\":\"to assess\"},{\"tag\":\"li\",\"content\":\"to regard\"}]},{\"data\":{\"content\":\"extra-info\"},\"style\":{\"marginLeft\":\"0.5em\"},\"content\":{\"tag\":\"div\",\"content\":{\"data\":{\"sentence-key\":\"思います\",\"content\":\"example-sentence\",\"source\":\"146024\",\"source-type\":\"tat\"},\"style\":{\"borderRadius\":\"0.4rem\",\"marginTop\":\"0.5rem\",\"borderWidth\":\"calc(3em / var(--font-size-no-units, 14))\",\"borderStyle\":\"none none none solid\",\"borderColor\":\"var(--text-color, var(--fg, #333))\",\"padding\":\"0.5rem\",\"marginBottom\":\"0.5rem\",\"backgroundColor\":\"color-mix(in srgb, var(--text-color, var(--fg, #333)) 5%, transparent)\"},\"content\":[{\"data\":{\"content\":\"example-sentence-a\"},\"style\":{\"fontSize\":\"1.3em\"},\"content\":[\"状況は深刻だと\",{\"tag\":\"span\",\"style\":{\"color\":\"color-mix(in srgb, lime, var(--text-color, var(--fg, #333)))\"},\"content\":\"思います\"},\"か。\"],\"tag\":\"div\"},{\"data\":{\"content\":\"example-sentence-b\"},\"style\":{\"fontSize\":\"0.8em\"},\"content\":[\"Do you regard the situation as serious?\",{\"data\":{\"content\":\"attribution-footnote\"},\"style\":{\"marginLeft\":\"0.25rem\",\"color\":\"#777\",\"verticalAlign\":\"top\",\"fontSize\":\"0.8em\"},\"content\":\"[2]\",\"tag\":\"span\"}],\"tag\":\"div\"}],\"tag\":\"div\"}},\"tag\":\"div\"}],\"tag\":\"li\"},{\"data\":{\"sense-number\":\"4\"},\"style\":{\"paddingLeft\":\"0.25em\",\"listStyleType\":\"\\\"④\\\"\"},\"content\":[{\"tag\":\"ul\",\"data\":{\"content\":\"glossary\"},\"content\":[{\"tag\":\"li\",\"content\":\"to imagine\"},{\"tag\":\"li\",\"content\":\"to suppose\"},{\"tag\":\"li\",\"content\":\"to dream\"}]},{\"data\":{\"content\":\"extra-info\"},\"style\":{\"marginLeft\":\"0.5em\"},\"content\":{\"tag\":\"div\",\"content\":{\"data\":{\"sentence-key\":\"思っている\",\"content\":\"example-sentence\",\"source\":\"185953\",\"source-type\":\"tat\"},\"style\":{\"borderRadius\":\"0.4rem\",\"marginTop\":\"0.5rem\",\"borderWidth\":\"calc(3em / var(--font-size-no-units, 14))\",\"borderStyle\":\"none none none solid\",\"borderColor\":\"var(--text-color, var(--fg, #333))\",\"padding\":\"0.5rem\",\"marginBottom\":\"0.5rem\",\"backgroundColor\":\"color-mix(in srgb, var(--text-color, var(--fg, #333)) 5%, transparent)\"},\"content\":[{\"data\":{\"content\":\"example-sentence-a\"},\"style\":{\"fontSize\":\"1.3em\"},\"content\":[{\"tag\":\"ruby\",\"content\":[\"我々\",{\"tag\":\"rt\",\"content\":\"われわれ\"}]},\"が\",{\"data\":{\"content\":\"example-keyword\"},\"style\":{\"color\":\"color-mix(in srgb, lime, var(--text-color, var(--fg, #333)))\"},\"content\":[{\"tag\":\"ruby\",\"content\":[\"思\",{\"tag\":\"rt\",\"content\":\"おも\"}]},\"っている\"],\"tag\":\"span\"},\"ほどには、それほど\",{\"tag\":\"ruby\",\"content\":[\"我々\",{\"tag\":\"rt\",\"content\":\"われわれ\"}]},\"は\",{\"tag\":\"ruby\",\"content\":[\"幸\",{\"tag\":\"rt\",\"content\":\"こう\"}]},{\"tag\":\"ruby\",\"content\":[\"福\",{\"tag\":\"rt\",\"content\":\"ふく\"}]},\"でもなければ、\",{\"tag\":\"ruby\",\"content\":[\"不\",{\"tag\":\"rt\",\"content\":\"ふ\"}]},{\"tag\":\"ruby\",\"content\":[\"幸\",{\"tag\":\"rt\",\"content\":\"こう\"}]},\"でもない。\"],\"tag\":\"div\"},{\"data\":{\"content\":\"example-sentence-b\"},\"style\":{\"fontSize\":\"0.8em\"},\"content\":[\"We are never as happy or as unhappy as we imagine.\",{\"data\":{\"content\":\"attribution-footnote\"},\"style\":{\"marginLeft\":\"0.25rem\",\"color\":\"#777\",\"verticalAlign\":\"top\",\"fontSize\":\"0.8em\"},\"content\":\"[3]\",\"tag\":\"span\"}],\"tag\":\"div\"}],\"tag\":\"div\"}},\"tag\":\"div\"}],\"tag\":\"li\"},{\"data\":{\"sense-number\":\"5\"},\"style\":{\"paddingLeft\":\"0.25em\",\"listStyleType\":\"\\\"⑤\\\"\"},\"content\":{\"tag\":\"ul\",\"data\":{\"content\":\"glossary\"},\"content\":[{\"tag\":\"li\",\"content\":\"to expect\"},{\"tag\":\"li\",\"content\":\"to look forward to\"}]},\"tag\":\"li\"},{\"data\":{\"sense-number\":\"6\"},\"style\":{\"paddingLeft\":\"0.25em\",\"listStyleType\":\"\\\"⑥\\\"\"},\"content\":{\"tag\":\"ul\",\"data\":{\"content\":\"glossary\"},\"content\":[{\"tag\":\"li\",\"content\":\"to feel\"},{\"tag\":\"li\",\"content\":\"to be (in a state of mind)\"},{\"tag\":\"li\",\"content\":\"to desire\"},{\"tag\":\"li\",\"content\":\"to want\"}]},\"tag\":\"li\"},{\"data\":{\"sense-number\":\"7\"},\"style\":{\"paddingLeft\":\"0.25em\",\"listStyleType\":\"\\\"⑦\\\"\"},\"content\":{\"tag\":\"ul\",\"data\":{\"content\":\"glossary\"},\"content\":[{\"tag\":\"li\",\"content\":\"to care (deeply) for\"},{\"tag\":\"li\",\"content\":\"to yearn for\"},{\"tag\":\"li\",\"content\":\"to worry about\"},{\"tag\":\"li\",\"content\":\"to love\"}]},\"tag\":\"li\"},{\"data\":{\"sense-number\":\"8\"},\"style\":{\"paddingLeft\":\"0.25em\",\"listStyleType\":\"\\\"⑧\\\"\"},\"content\":{\"tag\":\"ul\",\"data\":{\"content\":\"glossary\"},\"content\":[{\"tag\":\"li\",\"content\":\"to recall\"},{\"tag\":\"li\",\"content\":\"to remember\"}]},\"tag\":\"li\"}]}]},{\"data\":{\"content\":\"forms\"},\"style\":{\"marginTop\":\"0.5rem\"},\"content\":[{\"title\":\"spelling and reading variants\",\"style\":{\"fontSize\":\"0.8em\",\"color\":\"white\",\"cursor\":\"help\",\"borderRadius\":\"0.3em\",\"fontWeight\":\"bold\",\"marginRight\":\"0.25em\",\"padding\":\"0.2em 0.3em\",\"wordBreak\":\"keep-all\",\"verticalAlign\":\"text-bottom\",\"backgroundColor\":\"#565656\"},\"content\":\"forms\",\"tag\":\"span\"},{\"tag\":\"div\",\"style\":{\"marginTop\":\"0.2em\"},\"content\":{\"tag\":\"table\",\"content\":[{\"tag\":\"tr\",\"content\":[{\"tag\":\"th\"},{\"tag\":\"th\",\"style\":{\"fontSize\":\"1.2em\",\"fontWeight\":\"normal\",\"textAlign\":\"center\"},\"content\":\"思う\"},{\"tag\":\"th\",\"style\":{\"fontSize\":\"1.2em\",\"fontWeight\":\"normal\",\"textAlign\":\"center\"},\"content\":\"想う\"},{\"tag\":\"th\",\"style\":{\"fontSize\":\"1.2em\",\"fontWeight\":\"normal\",\"textAlign\":\"center\"},\"content\":\"憶う\"},{\"tag\":\"th\",\"style\":{\"fontSize\":\"1.2em\",\"fontWeight\":\"normal\",\"textAlign\":\"center\"},\"content\":\"念う\"}]},{\"tag\":\"tr\",\"content\":[{\"tag\":\"th\",\"style\":{\"fontWeight\":\"normal\"},\"content\":\"おもう\"},{\"tag\":\"td\",\"style\":{\"textAlign\":\"center\"},\"content\":{\"title\":\"high priority form\",\"style\":{\"cursor\":\"help\",\"background\":\"radial-gradient(green 50%, white 100%)\",\"clipPath\":\"circle()\",\"padding\":\"0 0.5em\",\"fontWeight\":\"bold\",\"color\":\"white\"},\"content\":\"△\",\"tag\":\"div\"}},{\"tag\":\"td\",\"style\":{\"textAlign\":\"center\"},\"content\":{\"title\":\"valid form/reading combination\",\"style\":{\"cursor\":\"help\",\"background\":\"radial-gradient(var(--text-color, var(--fg, #333)) 50%, white 100%)\",\"clipPath\":\"circle()\",\"padding\":\"0 0.5em\",\"fontWeight\":\"bold\",\"color\":\"var(--background-color, var(--canvas, #f8f9fa))\"},\"content\":\"◇\",\"tag\":\"div\"}},{\"tag\":\"td\",\"style\":{\"textAlign\":\"center\"},\"content\":{\"title\":\"rarely used form\",\"style\":{\"cursor\":\"help\",\"background\":\"radial-gradient(purple 50%, white 100%)\",\"clipPath\":\"circle()\",\"padding\":\"0 0.5em\",\"fontWeight\":\"bold\",\"color\":\"white\"},\"content\":\"▽\",\"tag\":\"div\"}},{\"tag\":\"td\",\"style\":{\"textAlign\":\"center\"},\"content\":{\"title\":\"rarely used form\",\"style\":{\"cursor\":\"help\",\"background\":\"radial-gradient(purple 50%, white 100%)\",\"clipPath\":\"circle()\",\"padding\":\"0 0.5em\",\"fontWeight\":\"bold\",\"color\":\"white\"},\"content\":\"▽\",\"tag\":\"div\"}}]}]}}],\"tag\":\"li\"}],\"tag\":\"ul\"},{\"data\":{\"content\":\"attribution\"},\"style\":{\"fontSize\":\"0.7em\",\"textAlign\":\"right\"},\"content\":[{\"tag\":\"a\",\"href\":\"https://www.edrdg.org/jmwsgi/entr.py?svc=jmdict&q=1589350\",\"content\":\"JMdict\"},\" | Tatoeba \",{\"tag\":\"a\",\"href\":\"https://tatoeba.org/en/sentences/show/143025\",\"content\":\"[1]\"},{\"tag\":\"a\",\"href\":\"https://tatoeba.org/en/sentences/show/146024\",\"content\":\"[2]\"},{\"tag\":\"a\",\"href\":\"https://tatoeba.org/en/sentences/show/185953\",\"content\":\"[3]\"}],\"tag\":\"div\"}]}]".data(using: .utf8)!,
                        sequenceNumber: 1,
                        termTags: [],
                        dictionary: DictionaryDB(id: 1, revision: "", title: "Jitandex", format: 3), exportedToAnki: false
                    ),
                    deinflections: [Deinflection(text: "思っている", inflections: [
                        InflectionRule.iru, InflectionRule.te
                    ], types: [])])
            ]),
            ParsingResult(original: "のか", results: [
                TermDeinflection(term: TermDB(term: "のか", reading: "のか", definitionTags: [], wordTypes: [], score: 200, definitions: Data(), sequenceNumber: 1, termTags: [], dictionary: DictionaryDB(id: 1, revision: "", title: "", format: 3), exportedToAnki: false), deinflections: [Deinflection(text: "のか", inflections: [], types: [])])
            ]),
            ParsingResult(original: "ね", results: [
                TermDeinflection(term: TermDB(term: "ね", reading: "ね", definitionTags: [], wordTypes: [], score: 200, definitions: Data(), sequenceNumber: 1, termTags: [], dictionary: DictionaryDB(id: 1, revision: "", title: "", format: 3), exportedToAnki: false), deinflections: [Deinflection(text: "ね", inflections: [], types: [])])
            ]),
        ],
        selectedElement: 5
    )
    .environmentObject(SettingsModel())
}


struct ResultView: View {
    @State var result: TermDeinflection
    @State var fullSentence: String
    
    @Binding var definition: InflectionDescription?
    @EnvironmentObject var settings: SettingsModel
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("\(result.term.term) (\(result.term.reading))")
                    .font(.title)
                Spacer()
                
                Button("Export") {
                    guard
                        let profileName = settings.ankiProfile?.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                        let noteTypeName = settings.ankiNoteType?.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                        let deckName = settings.ankiDeck?.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                        return
                    }
                    
                    var fields = ""
                    
                    if let fieldWord = settings.ankiFieldWord, let fieldWorldEncoded = fieldWord.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                       let wordEncoded = result.term.term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                        fields += "&fld\(fieldWorldEncoded)=\(wordEncoded)"
                    }
                    if let fieldReading = settings.ankiFieldReading, let fieldReadingEncoded = fieldReading.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                       let readingEncoded = result.term.reading.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                        fields += "&fld\(fieldReadingEncoded)=\(readingEncoded)"
                    }
                    if let fieldMeaning = settings.ankiFieldMeaning, let fieldMeaningEncoded = fieldMeaning.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                       let firstMeaning = result.term.parseDefinition.first,
                       let meaningEncoded = firstMeaning.description.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                        fields += "&fld\(fieldMeaningEncoded)=\(meaningEncoded)"
                    }
                    if let fieldExample = settings.ankiFieldExample, let fieldExampleEncoded = fieldExample.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                       let exampleEncoded = fullSentence.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                        fields += "&fld\(fieldExampleEncoded)=\(exampleEncoded)"
                    }
                    
                    if fields.isEmpty {
                        return
                    }
                    guard
                        let url = URL(string: "anki://x-callback-url/addnote?profile=\(profileName)&deck=\(deckName)&type=\(noteTypeName)&x-success=\("riidaa://anki-callback?term=\(result.term.hashValue)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")\(fields)") else {
                        return
                    }
                    UIApplication.shared.open(url, options: [:])
                }
                .padding(.vertical, 7)
                .padding(.horizontal, 10)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(7)
                
            }
            ForEach(result.deinflections, id: \.inflections) { deinflection in
                HStack(spacing: 0) {
                    Text("🚂")
                        .font(.callout)
                    ForEach(deinflection.inflections.reversed()) { rule in
                        Text("«")
                            .font(.callout)
                            .padding([.horizontal], 3)
                        Button {
                            withAnimation {
                                definition = rule.description
                                print("ResultView tapped: term=\(result.term.term), reading=\(result.term.reading)") //! DELETE LATER
                            }
                        } label: {
                            Text(rule.description.short)
                                .font(.callout)
                        }
                    }
                }
                .foregroundStyle(Color(.gray))
            }
            HStack {
                ForEach(result.term.definitionTags) { tag in
                    if tag != "" {
                        Text(tag)
                            .font(.footnote)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.cyan)
                            .roundedCorners(5, corners: .allCorners)
                    }
                }
                Text(result.term.dictionary.title)
                    .font(.footnote)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.purple)
                    .roundedCorners(5, corners: .allCorners)
            }
            ForEach(result.term.parseDefinition, id: \.self) { definition in
                VStack {
                    switch (definition) {
                    case .text(let s):
                        Text(s.content)
                            .padding(.bottom, 10)
                    case .detailed(let d):
                        DetailedView(structuredContent: d)
                            .padding(.bottom, 10)
                    default:
                        Text("TO DO")
                            .padding(.bottom, 10)
                    }
                    
//                    Text("").onAppear() {
//                        print("def: \(definition)")
//                    }
                }
            }
            
        }.onOpenURL { url in
            guard url.scheme == "riidaa",
                  url.host() == "anki-callback",
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let termParam = components.queryItems?.first(where: { $0.name == "term" })?.value,
                  let termHash = Int(termParam) else {
                return
            }
            if termHash == result.term.hashValue {
                // TODO: Save exported state
            }

        }
    }
}

struct DetailedView: View, Identifiable {
    var id: UUID = UUID()
    
    @State var structuredContent: StructuredContent
    @EnvironmentObject var settings: SettingsModel
    
    var body: some View {
        switch structuredContent {
        case .text(let string):
            ParserText(text: string.content)
        case .array(let array):
            ParserList(array: array, prefix: nil)
        case .newline:
            Spacer()
        case .link(let l):
            DetailedView(structuredContent: l.data)
                .onTapGesture {
                    print("Open link \(l.href)")
                }
        case .container(let c):
            DetailedView(structuredContent: c.data)
                .background(c.backgroundColor)
                .roundedCorners(5, corners: .allCorners)
        case .inlineContainer(let c):
            DetailedView(structuredContent: c.data)
                .font(c.font)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(c.backgroundColor)
                .roundedCorners(5, corners: .allCorners)
        case .table(let table):
            DetailedView(structuredContent: table.data)
        case .numberedList(let c):
            ParserNumberedList(array: c.content)
        case .list(let c):
            ParserList(array: c.content, prefix: c.prefix)
        }
    }
    
}
