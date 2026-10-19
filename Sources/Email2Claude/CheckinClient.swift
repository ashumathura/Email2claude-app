import Foundation
import Email2ClaudeCore

enum CheckinClient {
    struct ServerError: LocalizedError {
        let status: Int
        var errorDescription: String? { "The server answered with status \(status)." }
    }

    static func send(_ request: CheckinRequest) async throws -> CheckinResponse {
        var urlRequest = URLRequest(url: BackendConfig.checkinURL, timeoutInterval: 20)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try Checkin.encoder.encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw ServerError(status: status) }
        return try Checkin.decoder.decode(CheckinResponse.self, from: data)
    }
}
