import SwiftUI

struct SelectedLookupView: View {
    let dictionaryForm: String
    let reading: String?

    @EnvironmentObject var settings: SettingsModel
    @State private var results: [TermDeinflection] = []
    @State private var definition: InflectionDescription?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if results.isEmpty {
                        Text("No dictionary entries found.")
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        ForEach(results, id: \.self) { result in
                            ResultView(
                                result: result,
                                fullSentence: dictionaryForm,
                                definition: $definition
                            )
                            .padding(.horizontal)
                            Divider()
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("\(dictionaryForm)\(reading.map { " (\($0))" } ?? "")")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            loadResults()
        }
    }

    private func loadResults() {
        let texts = [dictionaryForm, dictionaryForm.katakanaToHiragana()]
        let terms = SQLiteManager.shared.findTerms(texts: texts)

        // Filter to terms that match the dictionary form (by term or reading)
        let matching = terms.filter { t in
            t.term.katakanaToHiragana() == dictionaryForm.katakanaToHiragana() ||
            t.reading.katakanaToHiragana() == dictionaryForm.katakanaToHiragana()
        }

        // Wrap each as a TermDeinflection with no deinflections
        results = matching.map { term in
            TermDeinflection(term: term, deinflections: [])
        }
    }
}
