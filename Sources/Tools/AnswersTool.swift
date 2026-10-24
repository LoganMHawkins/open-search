import SwiftUI

struct AnswersTool: View {
    enum Depth: String, CaseIterable { case fast = "Fast", ultra = "Ultra" }

    @EnvironmentObject private var model: AppModel
    @State private var task = ""
    @State private var depth = Depth.fast
    @State private var useSchema = false
    @State private var schema = """
    {
      "type": "object",
      "properties": {
        "summary": { "type": "string" }
      }
    }
    """
    @State private var timeoutSeconds = ""
    @State private var confirmUltra = false

    private var runner: ToolRunner { model.runner(for: .answers) }

    private var parsedSchema: Any? {
        guard useSchema, let data = schema.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private var schemaValid: Bool { !useSchema || parsedSchema != nil }

    var body: some View {
        ToolScaffold(tool: .answers, runner: runner, canRun: task.nilIfBlank != nil && schemaValid,
                     costNote: depth == .fast ? "10 credits" : "100 credits", onRun: attempt) {
            Section("Research task") {
                QueryField(tool: .answers, title: "e.g. Who founded Context.dev and what has it raised?", text: $task, axis: .vertical)
                Picker("Depth", selection: $depth) {
                    ForEach(Depth.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(depth == .fast ? "Fast: a quick pass, 10 credits." : "Ultra: deep multi-step research, 100 credits.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Answer shape") {
                Toggle("Describe the answer as JSON Schema", isOn: $useSchema)
                if useSchema {
                    TextEditor(text: $schema)
                        .font(.system(.callout, design: .monospaced))
                        .frame(height: 150)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    if !schemaValid { Label("That isn't valid JSON yet.", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.red) }
                } else {
                    Text("Leave this off to let the model pick a sensible structure.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Advanced") {
                TextField("Timeout (seconds)", text: $timeoutSeconds, prompt: Text("Default"))
            }
        } results: { runner in
            if let result = runner.latest { AnswersResult(result: result.json) }
        }
        .alert("Run an Ultra answer?", isPresented: $confirmUltra) {
            Button("Run for 100 credits") { run() }
            Button("Use Fast instead (10)") { depth = .fast; run() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Ultra research uses 100 credits.")
        }
        .onHandoff(for: .answers) { v, go in
            task = v["task"] ?? task
            if go { attempt() }
        }
    }

    private func attempt() {
        guard task.nilIfBlank != nil, schemaValid else { return }
        if depth == .ultra { confirmUltra = true } else { run() }
    }

    private func run() {
        guard let t = task.nilIfBlank else { return }
        Recents.add(t, for: .answers)
        var body: [String: Any] = ["task": t, "mode": depth.rawValue.lowercased()]
        if let schema = parsedSchema { body["json_format"] = schema }
        if let secs = Double(timeoutSeconds.trimmingCharacters(in: .whitespaces)), secs >= 5 {
            body["timeoutOpts"] = ["milliseconds": Int(secs * 1000), "behavior": "return-partial"]
        }
        let client = model.client
        runner.run { _ in try await client.post("web/answers", body, timeout: 330) }
    }
}

struct AnswersResult: View {
    let result: JSON

    var body: some View {
        let content = result["json_content"]
        VStack(spacing: 14) {
            if result["partial"].flag == true {
                Chip(text: "Partial answer: the time limit was reached", systemImage: "hourglass", tint: .yellow)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SectionLabel("Answer")
                        Spacer()
                        CopyButton(text: content.pretty, label: "Copy answer")
                    }
                    if case .string(let s) = content { MarkdownView(s) }
                    else { JSONOutline(value: content) }
                }
            }
            let sources = result["sources"].strings
            if !sources.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("Sources (\(sources.count))")
                        ForEach(sources, id: \.self) { s in
                            if let u = URL(string: s) {
                                HStack(spacing: 8) {
                                    Image(systemName: "link").foregroundStyle(Brand.orange)
                                    Link(s, destination: u).lineLimit(1).truncationMode(.middle)
                                }
                                .font(.callout)
                            }
                        }
                    }
                }
            }
        }
    }
}
