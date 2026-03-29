import Foundation
import Network

/// Delegate for SSDP device discovery events.
public protocol SSDPDelegate: AnyObject, Sendable {
    func ssdpDidDiscover(message: SSDPMessage)
    func ssdpDidLose(usn: String)
}

// MARK: - SSDPAdvertiser

/// Advertises a UPnP device on the local network via SSDP NOTIFY multicast.
public final class SSDPAdvertiser: @unchecked Sendable {
    private let location: String
    private let usn: String
    private let server: String
    private let deviceType: String

    private var connection: NWConnection?
    private var aliveTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "net.netkit.ssdp.advertiser")

    public init(
        location: String,
        usn: String,
        server: String = "macOS/1.0 UPnP/1.0 BrainyTube/1.0",
        deviceType: String = SSDPConstants.mediaServerType
    ) {
        self.location = location
        self.usn = usn
        self.server = server
        self.deviceType = deviceType
    }

    /// Start advertising on the SSDP multicast group. Sends an initial NOTIFY alive
    /// and repeats at the given interval.
    public func start(interval: TimeInterval = 600) {
        let host = NWEndpoint.Host(SSDPConstants.multicastAddress)
        let port = NWEndpoint.Port(rawValue: SSDPConstants.multicastPort)!

        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true

        let conn = NWConnection(host: host, port: port, using: params)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .ready = state {
                self.sendAlive()
                self.scheduleAliveTimer(interval: interval)
            }
        }
        conn.start(queue: queue)
    }

    /// Stop advertising — sends NOTIFY byebye and tears down the connection.
    public func stop() {
        aliveTimer?.cancel()
        aliveTimer = nil

        if let conn = connection, conn.state == .ready {
            let byebye = SSDPMessage.notifyByebye(usn: usn, searchTarget: deviceType)
            conn.send(content: byebye, completion: .contentProcessed { _ in })
        }

        connection?.cancel()
        connection = nil
    }

    private func sendAlive() {
        guard let conn = connection else { return }
        let data = SSDPMessage.notifyAlive(
            location: location,
            usn: usn,
            searchTarget: deviceType,
            server: server
        )
        conn.send(content: data, completion: .contentProcessed { _ in })

        // Also advertise root device
        let rootData = SSDPMessage.notifyAlive(
            location: location,
            usn: usn,
            searchTarget: SSDPConstants.rootDeviceType,
            server: server
        )
        conn.send(content: rootData, completion: .contentProcessed { _ in })
    }

    private func scheduleAliveTimer(interval: TimeInterval) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.sendAlive()
        }
        timer.resume()
        aliveTimer = timer
    }
}

// MARK: - SSDPSearchResponder

/// Listens for M-SEARCH requests on the SSDP multicast group and replies with unicast responses.
/// Used by `DLNAServer` so that browsers (iPad/VLC/etc.) can discover the server on demand.
public final class SSDPSearchResponder: @unchecked Sendable {
    private let location: String
    private let usn: String
    private let server: String
    private let deviceType: String

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "net.netkit.ssdp.searchResponder")

    public init(
        location: String,
        usn: String,
        server: String = "macOS/1.0 UPnP/1.0 BrainyTube/1.0",
        deviceType: String = SSDPConstants.mediaServerType
    ) {
        self.location = location
        self.usn = usn
        self.server = server
        self.deviceType = deviceType
    }

    /// Start listening for M-SEARCH queries on the SSDP multicast port.
    public func start() {
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true

        guard let listener = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: SSDPConstants.multicastPort)!) else {
            return
        }
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        listener.start(queue: queue)
    }

    /// Stop listening.
    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveMessage(on: connection)
    }

    private func receiveMessage(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self, let data, error == nil else { return }

            if let message = SSDPMessage.parse(data), message.type == .search {
                // Check if the search target matches our device type or ssdp:all
                let st = message.searchTarget ?? ""
                if st == "ssdp:all" || st == self.deviceType || st == SSDPConstants.rootDeviceType {
                    let response = SSDPMessage.searchResponse(
                        location: self.location,
                        usn: self.usn,
                        searchTarget: self.deviceType,
                        server: self.server
                    )
                    connection.send(content: response, completion: .contentProcessed { _ in })
                }
            }

            self.receiveMessage(on: connection)
        }
    }
}

// MARK: - SSDPBrowser

/// Discovers UPnP devices on the local network by sending M-SEARCH and listening for NOTIFY.
public final class SSDPBrowser: @unchecked Sendable {
    public weak var delegate: SSDPDelegate?

    private let searchTarget: String
    private var listener: NWListener?
    private var searchConnection: NWConnection?
    private var discoveredUSNs: Set<String> = []
    private let queue = DispatchQueue(label: "net.netkit.ssdp.browser")

    public init(searchTarget: String = SSDPConstants.mediaServerType) {
        self.searchTarget = searchTarget
    }

    /// Start browsing — listens for SSDP multicast and sends M-SEARCH.
    public func start() {
        startListener()
        sendSearch()
    }

    /// Stop browsing.
    public func stop() {
        listener?.cancel()
        listener = nil
        searchConnection?.cancel()
        searchConnection = nil
        discoveredUSNs.removeAll()
    }

    /// Send an M-SEARCH request to discover devices.
    public func sendSearch() {
        let host = NWEndpoint.Host(SSDPConstants.multicastAddress)
        let port = NWEndpoint.Port(rawValue: SSDPConstants.multicastPort)!

        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true

        let conn = NWConnection(host: host, port: port, using: params)
        searchConnection = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .ready = state {
                let data = SSDPMessage.mSearch(searchTarget: self.searchTarget)
                conn.send(content: data, completion: .contentProcessed { _ in })
            }
        }
        conn.start(queue: queue)
    }

    private func startListener() {
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true

        // Listen on the SSDP multicast port
        guard let listener = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: SSDPConstants.multicastPort)!) else {
            return
        }
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        listener.start(queue: queue)
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveMessage(on: connection)
    }

    private func receiveMessage(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self, let data, error == nil else { return }

            if let message = SSDPMessage.parse(data) {
                self.queue.async {
                    switch message.type {
                    case .alive, .searchResponse:
                        let isNew = self.discoveredUSNs.insert(message.usn).inserted
                        if isNew {
                            self.delegate?.ssdpDidDiscover(message: message)
                        }
                    case .byebye:
                        self.discoveredUSNs.remove(message.usn)
                        self.delegate?.ssdpDidLose(usn: message.usn)
                    case .search:
                        break // We don't respond to searches as a browser
                    }
                }
            }

            self.receiveMessage(on: connection)
        }
    }
}
