
import Foundation
import UIKit
import Flutter
import NearbyInteraction
import MultipeerConnectivity

final class UWBManager: NSObject,
                        FlutterStreamHandler,
                        MCSessionDelegate,
                        MCNearbyServiceAdvertiserDelegate,
                        MCNearbyServiceBrowserDelegate,
                        NISessionDelegate {
    private let serviceType = "uwb-friend"

    private let peerID: MCPeerID
    private var mcSession: MCSession!

    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!

    private var niSession: NISession?

    private var discoveredPeers: [String: MCPeerID] = [:]
    private var eventSink: FlutterEventSink?

    private var isDiscovering = false
    private var connectedPeerName: String?

    // Camera assistance gives direction on iPhone 14 and later; off for now.
    private let useCameraAssistance = false

    override init() {
        let suffix = UUID().uuidString.prefix(5)

        peerID = MCPeerID(
            displayName: "\(UIDevice.current.name)-\(suffix)"
        )

        super.init()

        configureMultipeerConnectivity()
        createNearbyInteractionSession()
    }

    // MARK: - Setup

    private func configureMultipeerConnectivity() {
        mcSession = MCSession(
            peer: peerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )

        mcSession.delegate = self

        advertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: nil,
            serviceType: serviceType
        )

        advertiser.delegate = self

        browser = MCNearbyServiceBrowser(
            peer: peerID,
            serviceType: serviceType
        )

        browser.delegate = self
    }

    private func createNearbyInteractionSession() {
        let session = NISession()
        session.delegate = self
        niSession = session
    }

    // MARK: - Flutter EventChannel

    func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(
        withArguments arguments: Any?
    ) -> FlutterError? {
        eventSink = nil
        return nil
    }

    private func emit(_ event: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(event)
        }
    }

    // MARK: - Discovery

    func startDiscovery() {
        guard NISession.deviceCapabilities
            .supportsPreciseDistanceMeasurement else {
            emit([
                "type": "error",
                "message": "This device does not support UWB ranging."
            ])
            return
        }

        if niSession == nil {
            createNearbyInteractionSession()
        }

        guard !isDiscovering else { return }

        discoveredPeers.removeAll()

        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()

        isDiscovering = true

        emit([
            "type": "status",
            "message": "Searching for nearby iPhones..."
        ])
    }

    func stopDiscovery() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()

        isDiscovering = false

        emit([
            "type": "status",
            "message": "Discovery stopped"
        ])
    }

    // MARK: - Connect / Disconnect

    func connect(to peerName: String) {
        guard let peer = discoveredPeers[peerName] else {
            emit([
                "type": "error",
                "message": "Device is no longer available."
            ])
            return
        }

        if mcSession.connectedPeers.contains(peer) {
            return
        }

        browser.invitePeer(
            peer,
            to: mcSession,
            withContext: nil,
            timeout: 30
        )

        emit([
            "type": "status",
            "message": "Connecting to \(peerName)..."
        ])
    }

    func disconnect() {
        stopDiscovery()
        connectedPeerName = nil

        mcSession.disconnect()

        niSession?.invalidate()
        niSession = nil

        emit([
            "type": "disconnected"
        ])
    }

    // MARK: - MCNearbyServiceBrowserDelegate

    func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        discoveredPeers[peerID.displayName] = peerID

        emit([
            "type": "peerFound",
            "peerId": peerID.displayName
        ])
    }

    func browser(
        _ browser: MCNearbyServiceBrowser,
        lostPeer peerID: MCPeerID
    ) {
        discoveredPeers.removeValue(
            forKey: peerID.displayName
        )

        emit([
            "type": "peerLost",
            "peerId": peerID.displayName
        ])
    }

    // MARK: - MCNearbyServiceAdvertiserDelegate

    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        // Only accept one peer at a time; a second invite while ranging
        // would disturb the active session.
        let busy = !mcSession.connectedPeers.isEmpty
        invitationHandler(!busy, busy ? nil : mcSession)
    }

    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didNotStartAdvertisingPeer error: Error
    ) {
        emit([
            "type": "error",
            "message": "Could not advertise: \(error.localizedDescription)"
        ])
    }

    func browser(
        _ browser: MCNearbyServiceBrowser,
        didNotStartBrowsingForPeers error: Error
    ) {
        emit([
            "type": "error",
            "message": "Could not browse: \(error.localizedDescription)"
        ])
    }

    // MARK: - MCSessionDelegate

    func session(
        _ session: MCSession,
        peer peerID: MCPeerID,
        didChange state: MCSessionState
    ) {
        // MCSession calls back on a private queue; hop to main so all
        // NISession/state access happens on one thread.
        DispatchQueue.main.async { [weak self] in
            self?.handleStateChange(peerID: peerID, state: state)
        }
    }

    private func handleStateChange(peerID: MCPeerID, state: MCSessionState) {
        switch state {
        case .connecting:
            emit([
                "type": "status",
                "message": "Connecting to \(peerID.displayName)..."
            ])

        case .connected:
            connectedPeerName = peerID.displayName

            // Stop discovery once paired; continued browsing/advertising
            // competes with the session for the radio.
            advertiser.stopAdvertisingPeer()
            browser.stopBrowsingForPeers()
            isDiscovering = false

            emit([
                "type": "connected",
                "peerId": peerID.displayName
            ])

            sendDiscoveryToken()

        case .notConnected:
            if connectedPeerName == peerID.displayName {
                // A live connection dropped.
                connectedPeerName = nil
                niSession?.invalidate()
                niSession = nil

                emit([
                    "type": "disconnected"
                ])
            } else {
                // An invite failed or timed out. Keep the NI session so the
                // next attempt can still send its discovery token.
                emit([
                    "type": "error",
                    "message": "Could not connect to \(peerID.displayName). Try again."
                ])
            }

        @unknown default:
            break
        }
    }

    private func sendDiscoveryToken() {
        if niSession == nil {
            createNearbyInteractionSession()
        }

        guard let token = niSession?.discoveryToken else {
            emit([
                "type": "error",
                "message": "Unable to create UWB discovery token."
            ])
            return
        }

        do {
            let data = try NSKeyedArchiver.archivedData(
                withRootObject: token,
                requiringSecureCoding: true
            )

            try mcSession.send(
                data,
                toPeers: mcSession.connectedPeers,
                with: .reliable
            )

            emit([
                "type": "status",
                "message": "UWB token sent. Waiting for peer..."
            ])

        } catch {
            emit([
                "type": "error",
                "message": "Token exchange failed: \(error.localizedDescription)"
            ])
        }
    }

    func session(
        _ session: MCSession,
        didReceive data: Data,
        fromPeer peerID: MCPeerID
    ) {
        do {
            guard let token = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: NIDiscoveryToken.self,
                from: data
            ) else {
                emit([
                    "type": "error",
                    "message": "Could not decode UWB token."
                ])
                return
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                if self.niSession == nil {
                    self.createNearbyInteractionSession()
                }

                guard let niSession = self.niSession else {
                    return
                }

                let configuration = NINearbyPeerConfiguration(
                    peerToken: token
                )

                if self.useCameraAssistance,
                   NISession.deviceCapabilities.supportsCameraAssistance {
                    configuration.isCameraAssistanceEnabled = true
                }

                niSession.run(configuration)

                self.emit([
                    "type": "status",
                    "message": "Starting UWB ranging..."
                ])
            }

        } catch {
            emit([
                "type": "error",
                "message": "Invalid UWB token: \(error.localizedDescription)"
            ])
        }
    }

    func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {}

    func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {}

    func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {}

    // MARK: - NISessionDelegate

    func session(
        _ session: NISession,
        didUpdate nearbyObjects: [NINearbyObject]
    ) {
        guard let object = nearbyObjects.first else { return }

        var event: [String: Any] = [
            "type": "ranging",
            "distance": object.distance.map { Double($0) } ?? NSNull()
        ]

        if let angle = object.horizontalAngle {
            event["horizontalAngle"] = Double(angle)
        }

        if let direction = object.direction {
            event["directionX"] = Double(direction.x)
            event["directionY"] = Double(direction.y)
            event["directionZ"] = Double(direction.z)
        }

        emit(event)
    }

    func session(
        _ session: NISession,
        didRemove nearbyObjects: [NINearbyObject],
        reason: NINearbyObject.RemovalReason
    ) {
        emit([
            "type": "status",
            "message": "Peer temporarily unavailable."
        ])
    }

    func sessionWasSuspended(_ session: NISession) {
        emit(["type": "status", "message": "UWB paused. Make sure Bluetooth is ON in Settings and the app is open on both phones."])
    }

    func sessionSuspensionEnded(_ session: NISession) {
        if let config = session.configuration {
            session.run(config)
        }
    }

    func session(
        _ session: NISession,
        didInvalidateWith error: Error
    ) {
        guard session === niSession else { return }
        niSession = nil

        emit([
            "type": "error",
            "message": "UWB session invalidated: \(error.localizedDescription)"
        ])
    }
}
