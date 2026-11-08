import Foundation

/// The transport kind: native AVPlayer or a WebKit embed.
enum TransportKind: String, Sendable {
    case native
    case web
}

/// A typed transport failure, decoupled from provider identity. The engine maps
/// this onto its `PlaybackState.PlaybackFailure`.
struct TransportFailure: Error, Sendable, Equatable {
    enum Category: String, Sendable {
        case manifestUnreachable
        case decodingFailed
        case relayFailed
        case timeout
        case cancelled
    }
    let category: Category
    let retryable: Bool
}

/// A delivery that has been validated and prepared for playback.
struct PreparedPlayback: Sendable {
    let session: StreamSession
    let kind: TransportKind
}

/// The transport seam. Native AVPlayer, WebKit embeds and the local header
/// relay all conform to this one interface. It is `@MainActor`-bound because
/// the real transports (AVPlayer, WKWebView) are main-actor types. The engine
/// drives state; the transport only executes the current command. It consumes
/// the app's rich `StreamSession`; the resolver/adapter layer produces those
/// sessions from `SourceCandidate`.
@MainActor
protocol StreamTransport {
    var kind: TransportKind { get }

    /// Validates and prepares the session's delivery (headers, relay, codec
    /// probe). Throws a typed `TransportFailure` when preparation fails.
    func prepare(_ session: StreamSession) async throws -> PreparedPlayback

    /// Starts playback of a prepared delivery.
    func play(_ prepared: PreparedPlayback) async

    /// Pauses without tearing down the delivery.
    func pause() async

    /// Stops and releases the delivery.
    func stop() async
}
