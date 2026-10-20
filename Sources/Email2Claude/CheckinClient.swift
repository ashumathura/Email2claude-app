import Foundation
import Email2ClaudeCore

enum CheckinClient {
    struct ServerError: LocalizedError {
        let status: Int
        /// The server's error code, such as bad_email or already_registered.
        var code: String?

        var errorDescription: String? {
            switch code {
            case "bad_email": return "That doesn't look like a valid email address."
            case "already_registered":
                return "A license key has already been issued for this email address. Enter that key in Settings → License, or contact the developer if you've lost it."
            default: return "The server answered with status \(status)."
            }
        }
    }

    static func send(_ request: CheckinRequest) async throws -> CheckinResponse {
        var urlRequest = URLRequest(url: BackendConfig.checkinURL, timeoutInterval: 20)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try Checkin.encoder.encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw ServerError(status: status, code: code)
        }
        return try Checkin.decoder.decode(CheckinResponse.self, from: data)
    }
}
