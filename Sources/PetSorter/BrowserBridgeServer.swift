import Foundation
import Network

/// 浏览器扩展直连收纳后返回的结果。
struct BrowserBridgeResponse: Codable {
    let success: Bool
    let message: String
}

/// 仅在本机回环地址上接收浏览器扩展的收纳请求。
final class BrowserBridgeServer {
    static let port: UInt16 = 48726

    private let queue = DispatchQueue(label: "com.local.PetSorter.browser-bridge")
    private let music: ([String: String]) -> BrowserBridgeResponse
    private let collect: ([String: String], @escaping (BrowserBridgeResponse) -> Void) -> Void
    private var listener: NWListener?

    init(music: @escaping ([String: String]) -> BrowserBridgeResponse, collect: @escaping ([String: String], @escaping (BrowserBridgeResponse) -> Void) -> Void) {
        self.collect = collect
        self.music = music
    }

    func start() {
        guard listener == nil, let port = NWEndpoint.Port(rawValue: Self.port) else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                self?.receive(from: connection, accumulated: Data())
                connection.start(queue: self?.queue ?? .global(qos: .utility))
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed = state { self?.listener = nil }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            listener = nil
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func receive(from connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var request = accumulated
            if let data { request.append(data) }
            // Base64 会比原图大约三分之一，32 MB 上限可覆盖常见网页图片且防止无界请求。
            guard request.count <= 32 * 1024 * 1024 else {
                self.send(.init(success: false, message: "投递内容过大"), status: 413, over: connection)
                return
            }
            if let parsed = self.parse(request) {
                self.handle(parsed, over: connection)
            } else if isComplete || error != nil {
                self.send(.init(success: false, message: "投递请求不完整"), status: 400, over: connection)
            } else {
                self.receive(from: connection, accumulated: request)
            }
        }
    }

    private struct Request {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    private func parse(_ data: Data) -> Request? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator),
              let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        let requestLine = (lines.first ?? "").split(separator: " ")
        guard requestLine.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let pair = line.split(separator: ":", maxSplits: 1).map(String.init)
            if pair.count == 2 {
                headers[pair[0].lowercased()] = pair[1].trimmingCharacters(in: .whitespaces)
            }
        }
        let bodyStart = headerRange.upperBound
        guard let expectedLength = Int(headers["content-length"] ?? "0"),
              expectedLength >= 0, expectedLength <= 32 * 1024 * 1024 else { return nil }
        guard data.count >= bodyStart + expectedLength else { return nil }
        return Request(
            method: String(requestLine[0]),
            path: String(requestLine[1]),
            headers: headers,
            body: data.subdata(in: bodyStart..<(bodyStart + expectedLength))
        )
    }

    private func handle(_ request: Request, over connection: NWConnection) {
        guard request.method == "POST", ["/collect", "/music"].contains(request.path) else {
            send(.init(success: false, message: "未知请求"), status: 404, over: connection)
            return
        }
        guard request.headers["x-yunchangwei-request"] == "browser-extension-v1" else {
            send(.init(success: false, message: "请求未经验证"), status: 403, over: connection)
            return
        }
        guard let object = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] else {
            send(.init(success: false, message: "投递参数无效"), status: 400, over: connection)
            return
        }
        var values: [String: String] = [:]
        for (key, value) in object {
            if let text = value as? String {
                values[key] = text
            } else if let data = try? JSONSerialization.data(withJSONObject: value),
                      let text = String(data: data, encoding: .utf8) {
                values[key] = text
            }
        }
        DispatchQueue.main.async { [weak self] in
            if request.path == "/music", let self {
                let response = self.music(values)
                self.send(response, status: response.success ? 200 : 422, over: connection)
                return
            }
            self?.collect(values) { response in
                self?.send(response, status: response.success ? 200 : 422, over: connection)
            }
        }
    }

    private func send(_ response: BrowserBridgeResponse, status: Int, over connection: NWConnection) {
        let body = (try? JSONEncoder().encode(response)) ?? Data("{\"success\":false,\"message\":\"未知错误\"}".utf8)
        let reason = status == 200 ? "OK" : "Error"
        let header = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var packet = Data(header.utf8)
        packet.append(body)
        connection.send(content: packet, completion: .contentProcessed { _ in connection.cancel() })
    }
}
