import Foundation

/// The OS session boundary permits deterministic routing tests without pretending
/// that Watch Simulator supports WCSession.transferFile.
public protocol WatchConnectivitySession: Sendable {
    var isAvailable: Bool { get }
    var isActivated: Bool { get }
    var isReachable: Bool { get }
    func activate(receive: @escaping @Sendable (ConnectivitySessionEvent) -> Void)
    func completeReceivedFile(_ url: URL) throws
    func transferUserInfo(_ data: Data) throws
    func sendMessage(_ data: Data)
    func transferFile(_ url: URL, metadata: Data) throws
    func updateApplicationContext(_ data: Data, credentials: Data?) throws
}
public extension WatchConnectivitySession { func completeReceivedFile(_ url: URL) throws {} }
public enum ConnectivitySessionEvent: Sendable {
    case activated, data(Data), file(URL, Data), context(Data, Data?), failed(UUID)
}

public final class WatchConnectivityAdapter: PeerTransport, Sendable {
    private let session: any WatchConnectivitySession
    public init(session: any WatchConnectivitySession) { self.session = session }
    public var isAvailable: Bool { session.isAvailable }
    public var isActivated: Bool { session.isActivated }
    public var isReachable: Bool { session.isReachable }
    public func activate(receive: @escaping @Sendable (PeerEvent) -> Void) {
        session.activate { event in
            do {
                switch event {
                case .activated: receive(.activated)
                case .failed(let id): receive(.transferFailed(id))
                case .data(let data): receive(.message(try .decode(data)))
                case .file(let url, let data): receive(.file(url, try .decode(data)))
                case .context(let data, let credentials):
                    let envelope = try ConnectivityEnvelope.decode(data)
                    if let credentials {
                        receive(.configuration(envelope, try PropertyListDecoder().decode(StoredWebhookCredentials.self, from: credentials)))
                    } else { receive(.message(envelope)) }
                }
            } catch { /* Unknown schema and malformed input do not change canonical state. */ }
        }
    }
    public func completeReceivedFile(_ url: URL) throws { try session.completeReceivedFile(url) }
    public func transfer(_ envelope: ConnectivityEnvelope) throws {
        let data = try envelope.encoded()
        try session.transferUserInfo(data)
        if session.isReachable { session.sendMessage(data) }
    }
    public func transferFile(at url: URL, metadata: ConnectivityEnvelope) throws {
        try session.transferFile(url, metadata: metadata.encoded())
    }
    public func updateContext(_ envelope: ConnectivityEnvelope, credentials: StoredWebhookCredentials?) throws {
        try session.updateApplicationContext(envelope.encoded(), credentials: credentials.map { try PropertyListEncoder().encode($0) })
    }
}

#if canImport(WatchConnectivity) && (os(iOS) || os(watchOS))
@preconcurrency import WatchConnectivity

public final class SystemWatchConnectivitySession: NSObject, WatchConnectivitySession, WCSessionDelegate, @unchecked Sendable {
    private let session: WCSession
    private let receivedFiles: ReceivedPeerFileStore
    private let inbox: ConnectivityInbox
    private let lock = NSLock()
    private var receiver: (@Sendable (ConnectivitySessionEvent) -> Void)?
    private var pendingObservation: NSKeyValueObservation?
    private let background = WatchBackgroundTaskCoordinator.shared

    public init(receivedRoot: URL, databaseURL: URL, session: WCSession = .default) throws {
        self.inbox = try ConnectivityInbox(databaseURL: databaseURL)
        self.receivedFiles = try ReceivedPeerFileStore(root: receivedRoot); self.session = session
        super.init()
    }
    public var isActivated: Bool { session.activationState == .activated }
    public var isAvailable: Bool {
        guard WCSession.isSupported() else { return false }
        #if os(iOS)
        return isActivated && session.isPaired && session.isWatchAppInstalled
        #else
        return isActivated && session.isCompanionAppInstalled
        #endif
    }
    public var isReachable: Bool { isActivated && session.isReachable }
    public func activate(receive: @escaping @Sendable (ConnectivitySessionEvent) -> Void) {
        lock.withLock { receiver = receive }
        guard WCSession.isSupported() else { return }
        session.delegate = self
        pendingObservation = session.observe(\.hasContentPending, options: [.initial, .new]) { [weak self] _, _ in self?.updateBackground() }
        session.activate()
        for file in (try? receivedFiles.pending()) ?? [] { emit(.file(file.url, file.metadata)) }
    }
    public func completeReceivedFile(_ url: URL) throws { try receivedFiles.complete(url) }
    public func transferUserInfo(_ data: Data) throws {
        guard isActivated else { throw ConnectivityError.inactiveSession }
        session.transferUserInfo(["envelope": data])
    }
    public func sendMessage(_ data: Data) { session.sendMessage(["envelope": data], replyHandler: nil, errorHandler: { _ in }) }
    public func transferFile(_ url: URL, metadata: Data) throws {
        guard isActivated else { throw ConnectivityError.inactiveSession }
        session.transferFile(url, metadata: ["envelope": metadata])
    }
    public func updateApplicationContext(_ data: Data, credentials: Data?) throws {
        guard isActivated else { throw ConnectivityError.inactiveSession }
        var context: [String: Any] = ["envelope": data]
        if let credentials { context["credentials"] = credentials }
        try session.updateApplicationContext(context)
    }
    private func emit(_ event: ConnectivitySessionEvent) { lock.withLock { receiver }?(event) }
    private func updateBackground() {
        background.update(activated: isActivated, hasContentPending: !isActivated || session.hasContentPending)
    }
    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            emit(.activated)
            if let data = session.receivedApplicationContext["envelope"] as? Data {
                emit(.context(data, session.receivedApplicationContext["credentials"] as? Data))
            }
        }
        updateBackground()
    }
    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        if let data = userInfo["envelope"] as? Data { capture(data) }
    }
    public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let data = message["envelope"] as? Data { capture(data) }
    }
    private func capture(_ data: Data) {
        do { try inbox.capture(data); emit(.data(data)) }
        catch { /* No acknowledgement: sender retains and replays on activation. */ }
    }
    public func sessionReachabilityDidChange(_ session: WCSession) {
        if isActivated { emit(.activated) }
    }
    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let data = applicationContext["envelope"] as? Data { emit(.context(data, applicationContext["credentials"] as? Data)) }
    }
    public func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let data = file.metadata?["envelope"] as? Data else { return }
        do {
            let destination = try receivedFiles.takeOwnership(of: file.fileURL, metadata: data)
            emit(.file(destination, data))
        } catch { /* Keep any owned remnant for recovery; never claim imported audio. */ }
    }
    public func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        if error != nil, let data = userInfoTransfer.userInfo["envelope"] as? Data,
           let envelope = try? ConnectivityEnvelope.decode(data) { emit(.failed(envelope.messageID)) }
    }
    public func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        if error != nil, let data = fileTransfer.file.metadata?["envelope"] as? Data,
           let envelope = try? ConnectivityEnvelope.decode(data) { emit(.failed(envelope.messageID)) }
    }
    #if os(iOS)
    public func sessionWatchStateDidChange(_ session: WCSession) {
        if isAvailable { emit(.activated) }
    }
    public func sessionDidBecomeInactive(_ session: WCSession) { updateBackground() }
    public func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #else
    public func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
        if isAvailable { emit(.activated) }
    }
    #endif
}
#endif
