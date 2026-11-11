import Foundation

/// Bounded request bodies, including servers that ignore Range or omit length.
/// Completion owns the underlying task: timeout, cancellation and prefix success
/// all retire it immediately. A late URLSession callback cannot resume twice.
final class FottyBoundedHTTPClient: @unchecked Sendable {
    enum BodyMode: Sendable, Equatable { case complete, prefix }
    enum Failure: Error, Equatable {
        case invalidResponse, responseTooLarge, unsafeRedirect
        case httpStatus(Int)
    }
    struct Response: Sendable {
        let data: Data
        let http: HTTPURLResponse
    }
    typealias RedirectPolicy = @Sendable (URL, URL) -> Bool

    private final class Pending {
        let continuation: CheckedContinuation<Response, Error>
        let task: URLSessionDataTask
        let maximumBytes: Int
        let mode: BodyMode
        let acceptedStatusCodes: Set<Int>
        let redirectPolicy: RedirectPolicy?
        var redirects = 0
        var response: HTTPURLResponse?
        var data = Data()
        var deadline: DispatchWorkItem?

        init(continuation: CheckedContinuation<Response, Error>, task: URLSessionDataTask,
             maximumBytes: Int, mode: BodyMode, acceptedStatusCodes: Set<Int>,
             redirectPolicy: RedirectPolicy?) {
            self.continuation = continuation; self.task = task
            self.maximumBytes = maximumBytes; self.mode = mode
            self.acceptedStatusCodes = acceptedStatusCodes; self.redirectPolicy = redirectPolicy
        }
    }

    private final class CancellationOwner: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        private var action: (@Sendable () -> Void)?
        func install(_ action: @escaping @Sendable () -> Void) -> Bool {
            lock.lock()
            let allowed = !cancelled
            if allowed { self.action = action }
            lock.unlock()
            if !allowed { action() }
            return allowed
        }
        func cancel() {
            lock.lock()
            cancelled = true
            let action = self.action
            self.action = nil
            lock.unlock()
            action?()
        }
    }

    private final class Delegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        weak var owner: FottyBoundedHTTPClient?
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                        didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            guard let owner else { completionHandler(.cancel); return }
            completionHandler(owner.received(response, task: dataTask) ? .allow : .cancel)
        }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            owner?.received(data, task: dataTask)
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            owner?.completed(task, error: error)
        }
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            guard let owner else { completionHandler(nil); return }
            completionHandler(owner.redirect(task, response: response, request: request) ? request : nil)
        }
    }

    private let lock = NSLock()
    private var pending: [Int: Pending] = [:]
    private let delegate: Delegate
    private let session: URLSession
    private let deadlineQueue = DispatchQueue(label: "com.fotty.http.deadline")

    init(configuration: URLSessionConfiguration) {
        let delegate = Delegate()
        self.delegate = delegate
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        delegate.owner = self
    }

    deinit { session.invalidateAndCancel() }

    func fetch(_ request: URLRequest, maximumBytes: Int, mode: BodyMode = .complete,
               deadline: TimeInterval,
               acceptedStatusCodes: Set<Int> = Set(200..<300),
               redirectPolicy: RedirectPolicy? = nil) async throws -> Response {
        guard maximumBytes > 0, deadline.isFinite, deadline > 0 else { throw Failure.invalidResponse }
        let cancellation = CancellationOwner()
        let response = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request)
                let state = Pending(continuation: continuation, task: task, maximumBytes: maximumBytes,
                                    mode: mode, acceptedStatusCodes: acceptedStatusCodes,
                                    redirectPolicy: redirectPolicy)
                let timer = DispatchWorkItem { [weak self] in
                    self?.finish(task.taskIdentifier, result: .failure(URLError(.timedOut)))
                }
                state.deadline = timer
                lock.lock(); pending[task.taskIdentifier] = state; lock.unlock()
                guard cancellation.install({ [weak self] in
                    self?.finish(task.taskIdentifier, result: .failure(CancellationError()))
                }) else { return }
                deadlineQueue.asyncAfter(deadline: .now() + deadline, execute: timer)
                task.resume()
            }
        } onCancel: { cancellation.cancel() }
        try Task.checkCancellation()
        return response
    }

    private func finish(_ identifier: Int, result: Result<Response, Error>) {
        lock.lock()
        let state = pending.removeValue(forKey: identifier)
        lock.unlock()
        guard let state else { return }
        state.deadline?.cancel()
        state.task.cancel()
        state.continuation.resume(with: result)
    }

    private func received(_ response: URLResponse, task: URLSessionDataTask) -> Bool {
        lock.lock()
        guard let state = pending[task.taskIdentifier] else { lock.unlock(); return false }
        let failure: Failure?
        if let http = response as? HTTPURLResponse {
            if !state.acceptedStatusCodes.contains(http.statusCode) { failure = .httpStatus(http.statusCode) }
            else if state.mode == .complete && http.expectedContentLength > Int64(state.maximumBytes) {
                failure = .responseTooLarge
            } else { state.response = http; failure = nil }
        } else { failure = .invalidResponse }
        lock.unlock()
        if let failure { finish(task.taskIdentifier, result: .failure(failure)); return false }
        return true
    }

    private func received(_ data: Data, task: URLSessionDataTask) {
        lock.lock()
        guard let state = pending[task.taskIdentifier], let response = state.response else { lock.unlock(); return }
        let remaining = state.maximumBytes - state.data.count
        let result: Result<Response, Error>?
        if state.mode == .complete, data.count > remaining { result = .failure(Failure.responseTooLarge) }
        else {
            state.data.append(data.prefix(remaining))
            result = state.mode == .prefix && state.data.count == state.maximumBytes
                ? .success(Response(data: state.data, http: response)) : nil
        }
        lock.unlock()
        if let result { finish(task.taskIdentifier, result: result) }
    }

    private func completed(_ task: URLSessionTask, error: Error?) {
        lock.lock()
        let result: Result<Response, Error>?
        if let state = pending[task.taskIdentifier] {
            if let error { result = .failure(error) }
            else if let response = state.response { result = .success(Response(data: state.data, http: response)) }
            else { result = .failure(Failure.invalidResponse) }
        } else { result = nil }
        lock.unlock()
        if let result { finish(task.taskIdentifier, result: result) }
    }

    private func redirect(_ task: URLSessionTask, response: HTTPURLResponse, request: URLRequest) -> Bool {
        lock.lock()
        guard let state = pending[task.taskIdentifier] else { lock.unlock(); return false }
        state.redirects += 1
        let allowed = state.redirects <= 5 && response.url.flatMap { source in
            request.url.map { state.redirectPolicy?(source, $0) ?? true }
        } == true
        lock.unlock()
        if !allowed { finish(task.taskIdentifier, result: .failure(Failure.unsafeRedirect)) }
        return allowed
    }
}
