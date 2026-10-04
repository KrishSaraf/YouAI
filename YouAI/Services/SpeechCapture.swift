import AVFoundation
import Foundation
import Speech

/// Turns the microphone into words on the phone. The recording is not uploaded.
@MainActor
@Observable
final class SpeechCapture {
    var transcript = ""
    var isListening = false
    var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-SG"))
        ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapInstalled = false

    func toggle() {
        if isListening {
            stop()
        } else {
            Task { await start() }
        }
    }

    func start() async {
        errorMessage = nil
        guard recognizer?.isAvailable == true else {
            errorMessage = "Speech recognition isn't available right now."
            return
        }
        guard await Self.allowSpeech() else {
            errorMessage = "Turn on speech recognition in Settings to log by voice."
            return
        }
        guard await Self.allowMicrophone() else {
            errorMessage = "Turn on the microphone in Settings to log by voice."
            return
        }

        finishListening(cancel: true)
        transcript = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            tapInstalled = true
            engine.prepare()
            try engine.start()
        } catch {
            errorMessage = "Couldn't use the microphone. Try again."
            finishListening(cancel: true)
            return
        }

        isListening = true
        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if result?.isFinal == true {
                    self.isListening = false
                    self.finishListening(cancel: false)
                } else if error != nil, self.transcript.isEmpty, self.isListening {
                    self.errorMessage = "Couldn't hear that. Try again."
                    self.isListening = false
                    self.finishListening(cancel: false)
                }
            }
        }
    }

    func stop() {
        request?.endAudio()
        isListening = false
        finishListening(cancel: false)
    }

    private func finishListening(cancel: Bool) {
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if cancel { task?.cancel() }
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func allowSpeech() async -> Bool {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current == .authorized { return true }
        if current == .restricted || current == .denied { return false }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private static func allowMicrophone() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }
}
