import Foundation
import Security

enum SupabaseJSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: SupabaseJSONValue])
    case array([SupabaseJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if (try? value.decodeNil()) == true { self = .null }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
        else if let number = try? value.decode(Double.self) { self = .number(number) }
        else if let object = try? value.decode([String: SupabaseJSONValue].self) { self = .object(object) }
        else if let array = try? value.decode([SupabaseJSONValue].self) { self = .array(array) }
        else { throw DecodingError.dataCorruptedError(in: value, debugDescription: "Valor JSON não suportado") }
    }

    var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }
}

/// Minimal Supabase Auth and PostgREST client. The publishable key is safe to ship
/// in the app; row access is enforced by the database's RLS policies.
@MainActor
final class SupabaseService {
    static let shared = SupabaseService()

    private let projectURL = URL(string: "https://pdxamdlhuuhrwqtlnpnt.supabase.co")!
    static let authRedirectURL = URL(string: "seta://auth-callback")!
    private let publishableKey = "sb_publishable_HqH6q5ccJ5ABi8FtJsL_3g_YsYBiCpF"
    private let tokenKey = "seta.supabase.session"
    private var accessToken: String? { get { keychainValue(for: tokenKey) } set { setKeychainValue(newValue, for: tokenKey) } }
    private var refreshToken: String? { get { keychainValue(for: tokenKey + ".refresh") } set { setKeychainValue(newValue, for: tokenKey + ".refresh") } }

    private init() {}
    var hasActiveSession: Bool { accessToken != nil }

    struct Session: Decodable {
        let access_token: String
        let refresh_token: String?
        let user: User
        struct User: Decodable { let id: UUID; let email: String?; let user_metadata: [String: SupabaseJSONValue]? }
    }

    struct AuthenticatedUser {
        let id: UUID
        let email: String
        let name: String
    }

    struct Profile {
        let name: String
        let role: String
        let phone: String
    }

    enum ServiceError: LocalizedError {
        case noSession, badResponse, server(String)
        var errorDescription: String? {
            switch self {
            case .noSession: return "Sua sessão expirou. Entre novamente."
            case .badResponse: return "O Supabase retornou uma resposta inesperada."
            case .server(let message): return message
            }
        }
    }

    func signUp(email: String, password: String, name: String, role: String, phone: String) async throws -> AuthenticatedUser? {
        let payload: [String: Any] = ["email": email, "password": password,
            "data": ["full_name": name, "profession": role, "phone_number": phone]]
        var components = URLComponents()
        components.path = "/auth/v1/signup"
        components.queryItems = [URLQueryItem(name: "redirect_to", value: Self.authRedirectURL.absoluteString)]
        let path = components.string ?? "/auth/v1/signup"
        let data = try await send(path: path, method: "POST", body: payload, authenticated: false)
        if let session = try? JSONDecoder().decode(Session.self, from: data) { save(session); return user(from: session) }
        return nil // Email confirmation may be enabled in Supabase.
    }

    func handleAuthCallback(_ url: URL) async throws -> AuthenticatedUser? {
        guard url.scheme == Self.authRedirectURL.scheme,
              url.host == Self.authRedirectURL.host,
              let fragment = url.fragment,
              let items = URLComponents(string: "?\(fragment)")?.queryItems,
              let accessToken = items.first(where: { $0.name == "access_token" })?.value,
              let refreshToken = items.first(where: { $0.name == "refresh_token" })?.value else { return nil }

        self.accessToken = accessToken
        self.refreshToken = refreshToken
        do {
            return try await currentUser()
        } catch {
            self.accessToken = nil
            self.refreshToken = nil
            throw error
        }
    }

    func signIn(email: String, password: String) async throws -> AuthenticatedUser {
        let data = try await send(path: "/auth/v1/token?grant_type=password", method: "POST",
                                  body: ["email": email, "password": password], authenticated: false)
        let session = try JSONDecoder().decode(Session.self, from: data); save(session); return user(from: session)
    }

    func signInWithIDToken(provider: String, idToken: String, nonce: String? = nil) async throws -> AuthenticatedUser {
        var body: [String: Any] = ["provider": provider, "id_token": idToken]
        if let nonce { body["nonce"] = nonce }
        let data = try await send(path: "/auth/v1/token?grant_type=id_token", method: "POST", body: body, authenticated: false)
        let session = try JSONDecoder().decode(Session.self, from: data); save(session); return user(from: session)
    }

    func signOut() async {
        if accessToken != nil { _ = try? await send(path: "/auth/v1/logout", method: "POST", authenticated: true) }
        accessToken = nil; refreshToken = nil
    }

    func createTeam(name: String, description: String) async throws -> UUID {
        let user = try await currentUser()
        let data = try await send(path: "/rest/v1/teams?select=id", method: "POST",
            // Set the owner explicitly from the currently validated session.
            // This matches the INSERT policy and also works if the database's
            // owner_id default has not yet been applied in a given environment.
            body: [["name": name, "description": description, "owner_id": user.id.uuidString]], authenticated: true,
            prefer: "return=representation")
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let id = rows.first?["id"] as? String, let uuid = UUID(uuidString: id) else { throw ServiceError.badResponse }
        return uuid
    }

    /// Links a team created locally before Supabase was configured. Reuse an
    /// unambiguous matching team owned by the signed-in user; otherwise create it.
    func linkOrCreateTeam(name: String, description: String) async throws -> UUID {
        let teams = try await fetchTeams()
        let matches = teams.filter {
            ($0["name"] as? String) == name && ($0["description"] as? String ?? "") == description
        }
        if matches.count == 1,
           let id = matches[0]["id"] as? String,
           let uuid = UUID(uuidString: id) {
            return uuid
        }
        return try await createTeam(name: name, description: description)
    }

    func fetchTeams() async throws -> [[String: Any]] {
        let select = "id,name,description,created_at,team_members(id,email,full_name,phone_number,role,released_budget,is_active,expenses(id,description,amount,created_at,submitted_by,expense_receipts(id,file_name,storage_path,mime_type))),team_messages(id,author_name,body,created_at)"
        let data = try await send(path: "/rest/v1/teams?select=\(select)&order=created_at.desc", method: "GET", authenticated: true)
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw ServiceError.badResponse }
        return rows
    }

    func downloadReceipt(path: String) async throws -> Data {
        let safePath = path.split(separator: "/").map(String.init).joined(separator: "/")
        guard let url = URL(string: "/storage/v1/object/authenticated/expense-receipts/\(safePath)", relativeTo: projectURL) else { throw ServiceError.badResponse }
        var request = URLRequest(url: url); request.httpMethod = "GET"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        guard let accessToken else { throw ServiceError.noSession }
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ServiceError.server(String(data: data, encoding: .utf8) ?? "Falha ao baixar comprovante")
        }
        return data
    }

    func addMember(teamID: UUID, email: String, name: String, phone: String, role: String) async throws -> UUID {
        let user = try await currentUser()
        let data = try await send(path: "/rest/v1/team_members?select=id", method: "POST",
            body: [["team_id": teamID.uuidString, "email": email.lowercased(), "full_name": name,
                    "phone_number": phone, "role": role, "invited_by": user.id.uuidString]],
            authenticated: true, prefer: "return=representation")
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let id = rows.first?["id"] as? String, let uuid = UUID(uuidString: id) else { throw ServiceError.badResponse }
        return uuid
    }

    func setBudget(memberID: UUID, amount: Double) async throws {
        _ = try await send(path: "/rest/v1/team_members?id=eq.\(memberID.uuidString)", method: "PATCH",
            body: ["released_budget": amount], authenticated: true, prefer: "return=minimal")
    }

    func deactivateMember(memberID: UUID) async throws {
        _ = try await send(path: "/rest/v1/team_members?id=eq.\(memberID.uuidString)", method: "PATCH",
            body: ["is_active": false], authenticated: true, prefer: "return=minimal")
    }

    func updateTeam(id: UUID, name: String, description: String) async throws {
        _ = try await send(path: "/rest/v1/teams?id=eq.\(id.uuidString)", method: "PATCH",
            body: ["name": name, "description": description], authenticated: true, prefer: "return=minimal")
    }

    func sendMessage(teamID: UUID, authorName: String, body: String) async throws -> UUID {
        let user = try await currentUser()
        let data = try await send(path: "/rest/v1/team_messages?select=id", method: "POST",
            body: ["team_id": teamID.uuidString, "author_id": user.id.uuidString, "author_name": authorName, "body": body],
            authenticated: true, prefer: "return=representation")
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let id = rows.first?["id"] as? String, let uuid = UUID(uuidString: id) else { throw ServiceError.badResponse }
        return uuid
    }

    func submitExpense(memberID: UUID, description: String, amount: Double, images: [Data]) async throws -> (UUID, [String]) {
        let user = try await currentUser()
        let data = try await send(path: "/rest/v1/expenses?select=id", method: "POST",
            body: [["team_member_id": memberID.uuidString, "submitted_by": user.id.uuidString,
                    "description": description, "amount": amount]], authenticated: true, prefer: "return=representation")
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let idString = rows.first?["id"] as? String, let expenseID = UUID(uuidString: idString) else { throw ServiceError.badResponse }
        var objectPaths: [String] = []
        for (index, image) in images.enumerated() {
            let objectName = "\(expenseID.uuidString)/\(user.id.uuidString)/receipt-\(index + 1).jpg"
            objectPaths.append(objectName)
            try await uploadReceipt(image, objectName: objectName)
            _ = try await send(path: "/rest/v1/expense_receipts", method: "POST",
                body: ["expense_id": expenseID.uuidString, "storage_path": objectName,
                       "file_name": "Comprovante \(index + 1)", "mime_type": "image/jpeg", "uploaded_by": user.id.uuidString],
                authenticated: true, prefer: "return=minimal")
        }
        return (expenseID, objectPaths)
    }

    private func uploadReceipt(_ image: Data, objectName: String) async throws {
        guard let url = URL(string: "/storage/v1/object/expense-receipts/\(objectName)", relativeTo: projectURL) else { throw ServiceError.badResponse }
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        guard let accessToken else { throw ServiceError.noSession }
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("false", forHTTPHeaderField: "x-upsert")
        request.httpBody = image
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ServiceError.server(String(data: data, encoding: .utf8) ?? "Falha ao enviar comprovante")
        }
    }

    func updateProfile(name: String, role: String, phone: String) async throws {
        let user = try await currentUser()
        _ = try await send(path: "/rest/v1/profiles?id=eq.\(user.id.uuidString)", method: "PATCH",
            body: ["full_name": name, "profession": role, "phone_number": phone], authenticated: true,
            prefer: "return=minimal", extraHeaders: ["Prefer": "return=minimal", "Content-Profile": "public"])
    }

    func loadProfile() async throws -> Profile {
        let user = try await currentUser()
        let data = try await send(path: "/rest/v1/profiles?id=eq.\(user.id.uuidString)&select=full_name,profession,phone_number", method: "GET", authenticated: true)
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], let row = rows.first else { throw ServiceError.badResponse }
        return Profile(name: row["full_name"] as? String ?? user.name,
                       role: row["profession"] as? String ?? "Produtor geral",
                       phone: row["phone_number"] as? String ?? "")
    }

    private func currentUser() async throws -> AuthenticatedUser {
        guard accessToken != nil else { throw ServiceError.noSession }
        let data = try await send(path: "/auth/v1/user", method: "GET", authenticated: true)
        struct User: Decodable { let id: UUID; let email: String?; let user_metadata: [String: SupabaseJSONValue]? }
        let u = try JSONDecoder().decode(User.self, from: data)
        return .init(id: u.id, email: u.email ?? "", name: u.user_metadata?["full_name"]?.stringValue ?? u.user_metadata?["name"]?.stringValue ?? "")
    }

    private func user(from session: Session) -> AuthenticatedUser {
        .init(id: session.user.id, email: session.user.email ?? "",
              name: session.user.user_metadata?["full_name"]?.stringValue ?? session.user.user_metadata?["name"]?.stringValue ?? "")
    }

    private func save(_ session: Session) { accessToken = session.access_token; refreshToken = session.refresh_token }

    private func refreshSession() async throws {
        guard let refreshToken else { throw ServiceError.noSession }
        let data = try await send(path: "/auth/v1/token?grant_type=refresh_token", method: "POST",
                                  body: ["refresh_token": refreshToken], authenticated: false)
        let session = try JSONDecoder().decode(Session.self, from: data); save(session)
    }

    private func send(path: String, method: String, body: Any? = nil, authenticated: Bool = true,
                      prefer: String? = nil, extraHeaders: [String: String] = [:]) async throws -> Data {
        guard let url = URL(string: path, relativeTo: projectURL) else { throw ServiceError.badResponse }
        var request = URLRequest(url: url); request.httpMethod = method
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated {
            guard let accessToken else { throw ServiceError.noSession }
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        } else { request.setValue("Bearer \(publishableKey)", forHTTPHeaderField: "Authorization") }
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        for (key, value) in extraHeaders { request.setValue(value, forHTTPHeaderField: key) }
        if let body { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        var (data, response) = try await URLSession.shared.data(for: request)
        if authenticated, (response as? HTTPURLResponse)?.statusCode == 401, refreshToken != nil {
            _ = try? await refreshSession()
            if let accessToken {
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                (data, response) = try await URLSession.shared.data(for: request)
            }
        }
        guard let http = response as? HTTPURLResponse else { throw ServiceError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let parsed = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
            let message = (parsed?["msg"] as? String) ?? (parsed?["message"] as? String) ?? (parsed?["error_description"] as? String) ?? String(data: data, encoding: .utf8) ?? "Erro HTTP \(http.statusCode)"
            throw ServiceError.server(message)
        }
        return data
    }

    private func keychainValue(for key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "SetaSupabase", kSecAttrAccount as String: key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func setKeychainValue(_ value: String?, for key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "SetaSupabase", kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var item = query; item[kSecValueData as String] = data
        SecItemAdd(item as CFDictionary, nil)
    }
}
