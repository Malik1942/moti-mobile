import AVFoundation
import Foundation
import Speech

enum SpeechTranscriptionError: LocalizedError {
    case speechPermissionDenied
    case microphonePermissionDenied
    case recognizerUnavailable
    case audioInputUnavailable

    var errorDescription: String? {
        switch self {
        case .speechPermissionDenied, .microphonePermissionDenied:
            return "Microphone or speech recognition permission is needed for voice capture."
        case .recognizerUnavailable:
            return "Speech recognition is not available right now."
        case .audioInputUnavailable:
            return "I could not start the microphone."
        }
    }
}

@MainActor
final class SpeechTranscriptionService: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?

    init(locale: Locale = .current) {
        speechRecognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
    }

    func startTranscription() async throws {
        guard !isRecording else { return }
        guard await requestSpeechPermission() else {
            throw SpeechTranscriptionError.speechPermissionDenied
        }
        guard await requestMicrophonePermission() else {
            throw SpeechTranscriptionError.microphonePermissionDenied
        }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw SpeechTranscriptionError.recognizerUnavailable
        }

        stopTranscription()
        transcript = ""

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.channelCount > 0 else {
            throw SpeechTranscriptionError.audioInputUnavailable
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.stopTranscription()
                    }
                }

                if error != nil, self.isRecording {
                    self.stopTranscription()
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }

    func stopTranscription() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
