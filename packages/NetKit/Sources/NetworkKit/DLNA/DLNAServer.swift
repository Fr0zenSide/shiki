import Foundation
import Network

/// A DLNA/UPnP Media Server that combines SSDP advertising with an HTTP file server.
///
/// Serves:
/// - `/description.xml` — UPnP device description
/// - `/ContentDirectory/control` — SOAP Browse/Search endpoint
/// - `/media/{id}/{filename}` — Video/thumbnail file serving with Range support
///
/// ```swift
/// let server = DLNAServer(friendlyName: "My Server")
/// server.contentDirectory.setItems(mediaItems)
/// try await server.start()
/// ```
public final class DLNAServer: @unchecked Sendable {
    public let friendlyName: String
    public let uuid: String
    public let contentDirectory = ContentDirectory()

    private let queue = DispatchQueue(label: "net.netkit.dlna.server")
    private var listener: NWListener?
    private var advertiser: SSDPAdvertiser?
    private var searchResponder: SSDPSearchResponder?
    private var _port: UInt16 = 0

    /// Called when the server is ready and the port is assigned.
    public var onReady: ((UInt16) -> Void)?

    /// The port the server is listening on (available after `start()`).
    public var port: UInt16 { _port }

    /// The base URL for this server (e.g., "http://192.168.1.10:8080").
    public var baseURL: String {
        guard let address = localIPAddress() else { return "http://localhost:\(_port)" }
        return "http://\(address):\(_port)"
    }

    public init(
        friendlyName: String = "BrainyTube",
        uuid: String = UUID().uuidString
    ) {
        self.friendlyName = friendlyName
        self.uuid = uuid
    }

    // MARK: - Lifecycle

    /// Start the DLNA server on a random available port and begin SSDP advertising.
    public func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        let nwListener = try NWListener(using: params, on: .any)
        self.listener = nwListener

        nwListener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .ready = state {
                if let port = nwListener.port?.rawValue {
                    self._port = port
                    self.startAdvertiser()
                    self.onReady?(port)
                }
            }
        }

        nwListener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        nwListener.start(queue: queue)
    }

    /// Stop the DLNA server and SSDP advertising.
    public func stop() {
        advertiser?.stop()
        advertiser = nil
        searchResponder?.stop()
        searchResponder = nil
        listener?.cancel()
        listener = nil
    }

    // MARK: - SSDP Advertising

    private func startAdvertiser() {
        let location = "\(baseURL)/description.xml"
        let usn = "uuid:\(uuid)::\(SSDPConstants.mediaServerType)"

        let adv = SSDPAdvertiser(location: location, usn: usn)
        self.advertiser = adv
        adv.start()

        // Also start listening for M-SEARCH queries so browsers can discover us
        let responder = SSDPSearchResponder(location: location, usn: usn)
        self.searchResponder = responder
        responder.start()
    }

    // MARK: - HTTP Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHTTPRequest(on: connection)
    }

    private func receiveHTTPRequest(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, let request = String(data: data, encoding: .utf8) {
                self.routeRequest(request, rawData: data, on: connection)
            } else if isComplete || error != nil {
                connection.cancel()
            }
        }
    }

    private func routeRequest(_ request: String, rawData: Data, on connection: NWConnection) {
        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(connection: connection, status: "400 Bad Request", body: "Bad Request")
            return
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, status: "400 Bad Request", body: "Bad Request")
            return
        }

        let method = String(parts[0])
        let path = String(parts[1])

        // Parse headers
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colonIndex].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        switch (method, path) {
        case ("GET", "/description.xml"):
            handleDeviceDescription(connection: connection)

        case ("POST", "/ContentDirectory/control"):
            handleContentDirectoryControl(request: request, rawData: rawData, connection: connection)

        case ("GET", let p) where p.hasSuffix("/metadata.json") && p.hasPrefix("/media/"):
            handleMetadataRequest(path: p, connection: connection)

        case ("GET", let p) where p.hasPrefix("/media/"):
            handleMediaRequest(path: p, headers: headers, connection: connection)

        case ("HEAD", let p) where p.hasPrefix("/media/"):
            handleMediaRequest(path: p, headers: headers, connection: connection, headOnly: true)

        default:
            sendResponse(connection: connection, status: "404 Not Found", body: "Not Found")
        }
    }

    // MARK: - Device Description

    private func handleDeviceDescription(connection: NWConnection) {
        let xml = ContentDirectory.deviceDescriptionXML(
            friendlyName: friendlyName,
            uuid: uuid,
            baseURL: baseURL
        )
        sendResponse(
            connection: connection,
            status: "200 OK",
            contentType: "text/xml; charset=\"utf-8\"",
            body: xml
        )
    }

    // MARK: - Content Directory Control

    private func handleContentDirectoryControl(request: String, rawData: Data, connection: NWConnection) {
        // Extract SOAP body — look for Browse action
        let requestStr = String(data: rawData, encoding: .utf8) ?? request

        // Parse ObjectID from SOAP — simple extraction
        let objectID = extractXMLValue(from: requestStr, tag: "ObjectID") ?? "0"
        let startIndex = Int(extractXMLValue(from: requestStr, tag: "StartingIndex") ?? "0") ?? 0
        let requestedCount = Int(extractXMLValue(from: requestStr, tag: "RequestedCount") ?? "0") ?? 0

        let result = contentDirectory.browse(objectID: objectID, startIndex: startIndex, requestedCount: requestedCount)
        let didl = ContentDirectory.didlLite(items: result.items, baseURL: baseURL)
        let envelope = ContentDirectory.browseResponseEnvelope(
            didlLite: didl,
            totalMatches: result.totalMatches,
            numberReturned: result.numberReturned
        )

        sendResponse(
            connection: connection,
            status: "200 OK",
            contentType: "text/xml; charset=\"utf-8\"",
            body: envelope
        )
    }

    // MARK: - Sidecar Metadata JSON

    private func handleMetadataRequest(path: String, connection: NWConnection) {
        // Path format: /media/{id}/metadata.json
        let components = path.split(separator: "/").map(String.init)
        guard components.count >= 3, components[0] == "media" else {
            sendResponse(connection: connection, status: "404 Not Found", body: "Not Found")
            return
        }

        let itemID = components[1]
        let items = contentDirectory.allItems
        guard let item = items.first(where: { $0.id == itemID }) else {
            sendResponse(connection: connection, status: "404 Not Found", body: "Item Not Found")
            return
        }

        // Build JSON with standard fields + app-specific metadata
        var json: [String: Any] = [
            "id": item.id,
            "title": item.title,
            "mimeType": item.mimeType,
            "resourceURL": "\(baseURL)/media/\(item.id)/\(item.id).\(item.fileExtension)",
        ]

        if let creator = item.creator { json["creator"] = creator }
        if let duration = item.duration { json["duration"] = duration }
        if let fileSize = item.fileSize { json["fileSize"] = fileSize }
        if item.thumbnailPath != nil {
            json["thumbnailURL"] = "\(baseURL)/media/\(item.id)/thumbnail.jpg"
        }

        // Merge app-specific metadata
        for (key, value) in item.metadata {
            json[key] = value
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            sendResponse(connection: connection, status: "500 Internal Server Error", body: "JSON Error")
            return
        }

        sendResponse(
            connection: connection,
            status: "200 OK",
            contentType: "application/json",
            body: jsonString
        )
    }

    // MARK: - Media File Serving

    private func handleMediaRequest(path: String, headers: [String: String], connection: NWConnection, headOnly: Bool = false) {
        // Path format: /media/{id}/{filename}
        let components = path.split(separator: "/").map(String.init)
        guard components.count >= 3, components[0] == "media" else {
            sendResponse(connection: connection, status: "404 Not Found", body: "Not Found")
            return
        }

        let itemID = components[1]
        let filename = components[2]

        // Find the item
        let items = contentDirectory.allItems
        guard let item = items.first(where: { $0.id == itemID }) else {
            sendResponse(connection: connection, status: "404 Not Found", body: "Item Not Found")
            return
        }

        // Determine which file to serve
        let filePath: String
        if filename.hasPrefix("thumbnail") {
            guard let thumbPath = item.thumbnailPath else {
                sendResponse(connection: connection, status: "404 Not Found", body: "No Thumbnail")
                return
            }
            filePath = thumbPath
        } else {
            filePath = item.filePath
        }

        // Get file attributes
        let fm = FileManager.default
        guard fm.fileExists(atPath: filePath),
              let attrs = try? fm.attributesOfItem(atPath: filePath),
              let fileSize = attrs[.size] as? Int64 else {
            sendResponse(connection: connection, status: "404 Not Found", body: "File Not Found")
            return
        }

        let mimeType = filename.hasPrefix("thumbnail") ? "image/jpeg" : item.mimeType

        // Parse Range header
        if let rangeHeader = headers["range"] {
            handleRangeRequest(
                filePath: filePath,
                fileSize: fileSize,
                mimeType: mimeType,
                rangeHeader: rangeHeader,
                connection: connection,
                headOnly: headOnly
            )
        } else {
            // Full file response
            let responseHeaders = """
            HTTP/1.1 200 OK\r
            Content-Type: \(mimeType)\r
            Content-Length: \(fileSize)\r
            Accept-Ranges: bytes\r
            Connection: close\r
            \r

            """

            let headerData = Data(responseHeaders.utf8)
            connection.send(content: headerData, completion: .contentProcessed { [weak self] _ in
                if !headOnly {
                    self?.sendFile(at: filePath, offset: 0, length: Int(fileSize), on: connection)
                } else {
                    connection.cancel()
                }
            })
        }
    }

    private func handleRangeRequest(
        filePath: String,
        fileSize: Int64,
        mimeType: String,
        rangeHeader: String,
        connection: NWConnection,
        headOnly: Bool
    ) {
        // Parse "bytes=start-end" or "bytes=start-"
        guard rangeHeader.hasPrefix("bytes=") else {
            sendResponse(connection: connection, status: "416 Range Not Satisfiable", body: "Bad Range")
            return
        }

        let rangeSpec = String(rangeHeader.dropFirst(6))
        let parts = rangeSpec.split(separator: "-", maxSplits: 1)

        let start: Int64
        let end: Int64

        if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty {
            start = Int64(parts[0]) ?? 0
            end = min(Int64(parts[1]) ?? (fileSize - 1), fileSize - 1)
        } else if parts.count >= 1, !parts[0].isEmpty {
            start = Int64(parts[0]) ?? 0
            end = fileSize - 1
        } else if parts.count == 2, parts[0].isEmpty {
            // "bytes=-500" means last 500 bytes
            let suffix = Int64(parts[1]) ?? 0
            start = max(fileSize - suffix, 0)
            end = fileSize - 1
        } else {
            sendResponse(connection: connection, status: "416 Range Not Satisfiable", body: "Bad Range")
            return
        }

        guard start <= end, start < fileSize else {
            sendResponse(connection: connection, status: "416 Range Not Satisfiable", body: "Bad Range")
            return
        }

        let contentLength = end - start + 1
        let responseHeaders = """
        HTTP/1.1 206 Partial Content\r
        Content-Type: \(mimeType)\r
        Content-Length: \(contentLength)\r
        Content-Range: bytes \(start)-\(end)/\(fileSize)\r
        Accept-Ranges: bytes\r
        Connection: close\r
        \r

        """

        let headerData = Data(responseHeaders.utf8)
        connection.send(content: headerData, completion: .contentProcessed { [weak self] _ in
            if !headOnly {
                self?.sendFile(at: filePath, offset: Int(start), length: Int(contentLength), on: connection)
            } else {
                connection.cancel()
            }
        })
    }

    private func sendFile(at path: String, offset: Int, length: Int, on connection: NWConnection) {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            connection.cancel()
            return
        }

        handle.seek(toFileOffset: UInt64(offset))
        let chunkSize = 65536
        // Use a class wrapper so the closure can capture a mutable reference in a Sendable way
        final class ChunkState: @unchecked Sendable {
            var remaining: Int
            let handle: FileHandle
            init(remaining: Int, handle: FileHandle) {
                self.remaining = remaining
                self.handle = handle
            }
        }
        let state = ChunkState(remaining: length, handle: handle)

        @Sendable func sendChunk() {
            let toRead = min(chunkSize, state.remaining)
            guard toRead > 0 else {
                try? state.handle.close()
                connection.cancel()
                return
            }

            let data = state.handle.readData(ofLength: toRead)
            guard !data.isEmpty else {
                try? state.handle.close()
                connection.cancel()
                return
            }

            state.remaining -= data.count
            let isLast = state.remaining <= 0

            connection.send(content: data, isComplete: isLast, completion: .contentProcessed { error in
                if error != nil || isLast {
                    try? state.handle.close()
                    if isLast { connection.cancel() }
                } else {
                    sendChunk()
                }
            })
        }

        sendChunk()
    }

    // MARK: - HTTP Response

    private func sendResponse(
        connection: NWConnection,
        status: String,
        contentType: String = "text/plain",
        body: String
    ) {
        let bodyData = Data(body.utf8)
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: \(contentType)\r
        Content-Length: \(bodyData.count)\r
        Connection: close\r
        \r

        """
        var data = Data(response.utf8)
        data.append(bodyData)

        connection.send(content: data, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Helpers

    private func extractXMLValue(from xml: String, tag: String) -> String? {
        guard let startRange = xml.range(of: "<\(tag)>"),
              let endRange = xml.range(of: "</\(tag)>") else { return nil }
        let valueStart = startRange.upperBound
        let valueEnd = endRange.lowerBound
        guard valueStart < valueEnd else { return nil }
        return String(xml[valueStart..<valueEnd])
    }

    private func localIPAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var result: String?
        var current = ifaddr
        while let ptr = current {
            let addr = ptr.pointee
            let family = addr.ifa_addr.pointee.sa_family
            if family == UInt8(AF_INET) {
                let name = String(cString: addr.ifa_name)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let addrLen = socklen_t(addr.ifa_addr.pointee.sa_len)
                    if getnameinfo(addr.ifa_addr, addrLen, &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let nullIndex = hostname.firstIndex(of: 0) ?? hostname.endIndex
                        result = String(decoding: hostname[hostname.startIndex..<nullIndex].map { UInt8(bitPattern: $0) }, as: UTF8.self)
                        break
                    }
                }
            }
            current = addr.ifa_next
        }
        return result
    }
}
