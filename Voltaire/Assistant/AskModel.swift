import Foundation
import Observation

enum AskPhase: Equatable, Sendable {
    case ready
    case responding
    case response(String)
    case unavailable(AssistantAvailability)
    case failed(AssistantRequestError)
}

enum AskAccessibilityTarget: Hashable, Sendable {
    case response
    case unavailable
    case failure
}

extension AskPhase {
    var accessibilityTarget: AskAccessibilityTarget? {
        switch self {
        case .response:
            .response
        case .unavailable:
            .unavailable
        case .failed:
            .failure
        case .ready, .responding:
            nil
        }
    }
}

@MainActor
@Observable
final class AskModel {
    var isPresented = false
    var phase: AskPhase = .ready
    var customQuestion = ""
    private(set) var context: AskContext?

    @ObservationIgnored private let service: any AssistantService
    @ObservationIgnored private var requestTask: Task<Void, Never>?
    @ObservationIgnored private var activeRequestID: UUID?

    init(service: any AssistantService) {
        self.service = service
    }

    var canSubmitCustomQuestion: Bool {
        AskAction.customRequest(customQuestion) != nil && phase != .responding
    }

    func present(context: AskContext) {
        invalidateRequest()
        self.context = context
        customQuestion = ""
        isPresented = true
        refreshAvailability()
    }

    func refreshAvailability() {
        let availability = service.availability()
        phase = availability == .available ? .ready : .unavailable(availability)
    }

    func submitCustomQuestion() {
        guard let action = AskAction.customRequest(customQuestion) else { return }
        submit(action)
    }

    func submit(_ action: AskAction) {
        guard let context else { return }

        let availability = service.availability()
        guard availability == .available else {
            invalidateRequest()
            phase = .unavailable(availability)
            return
        }

        invalidateRequest()
        let requestID = UUID()
        activeRequestID = requestID
        phase = .responding

        requestTask = Task { [weak self, service, context] in
            do {
                let rawAnswer = try await service.answer(action: action, context: context)
                try Task.checkCancellation()
                let answer = rawAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !answer.isEmpty else { throw AssistantRequestError.emptyResponse }
                guard let self, self.activeRequestID == requestID else { return }
                self.activeRequestID = nil
                self.requestTask = nil
                self.phase = .response(answer)
            } catch is CancellationError {
                return
            } catch let error as AssistantRequestError {
                guard let self, self.activeRequestID == requestID else { return }
                self.activeRequestID = nil
                self.requestTask = nil
                self.phase = .failed(error)
            } catch {
                guard let self, self.activeRequestID == requestID else { return }
                self.activeRequestID = nil
                self.requestTask = nil
                self.phase = .failed(.failed)
            }
        }
    }

    func askAnother() {
        invalidateRequest()
        customQuestion = ""
        refreshAvailability()
    }

    func cancelRequest() {
        invalidateRequest()
        refreshAvailability()
    }

    func dismiss() {
        invalidateRequest()
        isPresented = false
        phase = .ready
        customQuestion = ""
        context = nil
    }

    func dismissIfContextChanged(currentSentenceID: String) {
        guard isPresented, context?.currentSentenceID != currentSentenceID else { return }
        dismiss()
    }

    private func invalidateRequest() {
        activeRequestID = nil
        requestTask?.cancel()
        requestTask = nil
    }
}
