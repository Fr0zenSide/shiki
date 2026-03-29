import Foundation
import Network

/// Delegate for DLNA server discovery events.
public protocol DLNABrowserDelegate: AnyObject, Sendable {
    func dlnaBrowser(_ browser: DLNABrowser, didDiscover server: DLNABrowser.DiscoveredServer)
    func dlnaBrowser(_ browser: DLNABrowser, didLose serverUSN: String)
}

/// Client-side DLNA discovery — finds media servers on the local network and browses their content.
public final class DLNABrowser: @unchecked Sendable {
    /// A discovered DLNA media server.
    public struct DiscoveredServer: Sendable, Equatable, Identifiable {
        public var id: String { usn }
        public let usn: String
        public let friendlyName: String
        public let location: String
        public let contentDirectoryURL: String

        public init(usn: String, friendlyName: String, location: String, contentDirectoryURL: String) {
            self.usn = usn
            self.friendlyName = friendlyName
            self.location = location
            self.contentDirectoryURL = contentDirectoryURL
        }
    }

    public weak var delegate: DLNABrowserDelegate?

    private let ssdpBrowser = SSDPBrowser(searchTarget: SSDPConstants.mediaServerType)
    private var discoveredServers: [String: DiscoveredServer] = [:]
    private let queue = DispatchQueue(label: "net.netkit.dlna.browser")

    public init() {}

    /// Start discovering DLNA servers.
    public func start() {
        ssdpBrowser.delegate = self
        ssdpBrowser.start()
    }

    /// Stop discovering.
    public func stop() {
        ssdpBrowser.stop()
        discoveredServers.removeAll()
    }

    /// Currently known servers.
    public var servers: [DiscoveredServer] {
        Array(discoveredServers.values)
    }

    /// Refresh — send another M-SEARCH.
    public func refresh() {
        ssdpBrowser.sendSearch()
    }

    // MARK: - Browse Server Content

    /// Browse a server's Content Directory via SOAP.
    public func browse(server: DiscoveredServer, objectID: String = "0") async throws -> [DLNAMediaItem] {
        let soapBody = """
        <?xml version="1.0" encoding="UTF-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
                    s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:Browse xmlns:u="\(SSDPConstants.contentDirectoryType)">
              <ObjectID>\(objectID)</ObjectID>
              <BrowseFlag>BrowseDirectChildren</BrowseFlag>
              <Filter>*</Filter>
              <StartingIndex>0</StartingIndex>
              <RequestedCount>0</RequestedCount>
              <SortCriteria></SortCriteria>
            </u:Browse>
          </s:Body>
        </s:Envelope>
        """

        guard let url = URL(string: server.contentDirectoryURL) else {
            throw DLNABrowserError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(SSDPConstants.contentDirectoryType)#Browse\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = Data(soapBody.utf8)

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let responseStr = String(data: data, encoding: .utf8) else {
            throw DLNABrowserError.invalidResponse
        }

        return DLNABrowser.parseDidlLiteFromSOAP(responseStr)
    }

    // MARK: - Device Description Fetching

    private func fetchDeviceDescription(location: String) async throws -> (friendlyName: String, controlURL: String) {
        guard let url = URL(string: location) else {
            throw DLNABrowserError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let xml = String(data: data, encoding: .utf8) else {
            throw DLNABrowserError.invalidResponse
        }

        let friendlyName = extractXMLValue(from: xml, tag: "friendlyName") ?? "Unknown"
        let controlURL = extractXMLValue(from: xml, tag: "controlURL") ?? "/ContentDirectory/control"

        // Build absolute control URL
        guard let baseURL = URL(string: location)?.deletingLastPathComponent() else {
            throw DLNABrowserError.invalidURL
        }

        let absoluteControlURL: String
        if controlURL.hasPrefix("http") {
            absoluteControlURL = controlURL
        } else {
            // Derive from location base
            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
            components?.path = controlURL
            absoluteControlURL = components?.url?.absoluteString ?? "\(baseURL)\(controlURL)"
        }

        return (friendlyName, absoluteControlURL)
    }

    // MARK: - XML Parsing Helpers

    private func extractXMLValue(from xml: String, tag: String) -> String? {
        guard let startRange = xml.range(of: "<\(tag)>"),
              let endRange = xml.range(of: "</\(tag)>") else { return nil }
        let valueStart = startRange.upperBound
        let valueEnd = endRange.lowerBound
        guard valueStart < valueEnd else { return nil }
        return String(xml[valueStart..<valueEnd])
    }

    /// Parse DIDL-Lite items from a SOAP Browse response.
    static func parseDidlLiteFromSOAP(_ soap: String) -> [DLNAMediaItem] {
        // Extract the Result element (contains XML-escaped DIDL-Lite)
        guard let resultStart = soap.range(of: "<Result>"),
              let resultEnd = soap.range(of: "</Result>") else { return [] }

        var didl = String(soap[resultStart.upperBound..<resultEnd.lowerBound])
        // Unescape XML entities
        didl = didl
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")

        return parseDidlLite(didl)
    }

    /// Parse DIDL-Lite XML into media items.
    static func parseDidlLite(_ didl: String) -> [DLNAMediaItem] {
        var items: [DLNAMediaItem] = []

        // Simple regex-free XML parsing for item elements
        var searchStart = didl.startIndex
        while let itemStart = didl.range(of: "<item ", range: searchStart..<didl.endIndex) {
            guard let itemEnd = didl.range(of: "</item>", range: itemStart.upperBound..<didl.endIndex) else { break }
            let itemXML = String(didl[itemStart.lowerBound...itemEnd.upperBound])

            if let item = parseSingleItem(itemXML) {
                items.append(item)
            }

            searchStart = itemEnd.upperBound
        }

        return items
    }

    private static func parseSingleItem(_ xml: String) -> DLNAMediaItem? {
        // Extract id attribute
        guard let idRange = xml.range(of: "id=\""),
              let idEnd = xml.range(of: "\"", range: idRange.upperBound..<xml.endIndex) else { return nil }
        let id = String(xml[idRange.upperBound..<idEnd.lowerBound])

        // Extract title
        let title = extractTag(from: xml, tag: "dc:title") ?? "Untitled"
        let creator = extractTag(from: xml, tag: "dc:creator")

        // Extract res URL and attributes
        let resURL = extractTag(from: xml, tag: "res")

        // Extract duration from res attributes
        var duration: TimeInterval?
        if let durationStr = extractAttribute(from: xml, element: "res", attribute: "duration") {
            duration = parseDuration(durationStr)
        }

        // Extract size
        var fileSize: Int64?
        if let sizeStr = extractAttribute(from: xml, element: "res", attribute: "size") {
            fileSize = Int64(sizeStr)
        }

        // Extract mimeType from protocolInfo
        var mimeType = "video/mp4"
        if let protocolInfo = extractAttribute(from: xml, element: "res", attribute: "protocolInfo") {
            let parts = protocolInfo.split(separator: ":")
            if parts.count >= 3 {
                mimeType = String(parts[2])
            }
        }

        return DLNAMediaItem(
            id: id,
            title: title,
            creator: creator,
            duration: duration,
            filePath: resURL ?? "",
            thumbnailPath: nil,
            mimeType: mimeType,
            fileSize: fileSize
        )
    }

    private static func extractTag(from xml: String, tag: String) -> String? {
        guard let startRange = xml.range(of: "<\(tag)>") ?? xml.range(of: "<\(tag) ") else { return nil }

        // If we matched "<tag ", find the closing ">" first
        let contentStart: String.Index
        if xml[startRange].last == " " {
            guard let closeAngle = xml.range(of: ">", range: startRange.upperBound..<xml.endIndex) else { return nil }
            contentStart = closeAngle.upperBound
        } else {
            contentStart = startRange.upperBound
        }

        guard let endRange = xml.range(of: "</\(tag)>", range: contentStart..<xml.endIndex) else { return nil }
        return String(xml[contentStart..<endRange.lowerBound])
    }

    private static func extractAttribute(from xml: String, element: String, attribute: String) -> String? {
        guard let elemStart = xml.range(of: "<\(element) ") ?? xml.range(of: "<\(element)\n") else { return nil }
        guard let elemEnd = xml.range(of: ">", range: elemStart.upperBound..<xml.endIndex) else { return nil }
        let elemHeader = String(xml[elemStart.lowerBound..<elemEnd.upperBound])

        guard let attrStart = elemHeader.range(of: "\(attribute)=\"") else { return nil }
        guard let attrEnd = elemHeader.range(of: "\"", range: attrStart.upperBound..<elemHeader.endIndex) else { return nil }
        return String(elemHeader[attrStart.upperBound..<attrEnd.lowerBound])
    }

    private static func parseDuration(_ str: String) -> TimeInterval {
        let parts = str.split(separator: ":")
        guard parts.count == 3 else { return 0 }
        let hours = Double(parts[0]) ?? 0
        let minutes = Double(parts[1]) ?? 0
        let seconds = Double(parts[2]) ?? 0
        return hours * 3600 + minutes * 60 + seconds
    }
}

// MARK: - SSDPDelegate

extension DLNABrowser: SSDPDelegate {
    public func ssdpDidDiscover(message: SSDPMessage) {
        guard let location = message.location else { return }

        Task {
            do {
                let (name, controlURL) = try await fetchDeviceDescription(location: location)
                let server = DiscoveredServer(
                    usn: message.usn,
                    friendlyName: name,
                    location: location,
                    contentDirectoryURL: controlURL
                )
                queue.async { [weak self] in
                    guard let self else { return }
                    self.discoveredServers[message.usn] = server
                    self.delegate?.dlnaBrowser(self, didDiscover: server)
                }
            } catch {
                // Silently ignore devices we can't parse
            }
        }
    }

    public func ssdpDidLose(usn: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.discoveredServers.removeValue(forKey: usn)
            self.delegate?.dlnaBrowser(self, didLose: usn)
        }
    }
}

// MARK: - Errors

public enum DLNABrowserError: Error, Sendable {
    case invalidURL
    case invalidResponse
    case networkError(String)
}
