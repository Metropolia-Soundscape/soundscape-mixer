import Foundation
import KeychainSwift

enum LoginState {
    case loggedOut
    case loggedIn(token: String)
}

extension LoginState {

    fileprivate init(token: String?) {
        if let token = token{
            self = .loggedIn(token: token)
        } else {
            self = .loggedOut
        }
    }

    var isLoggedIn: Bool {
        switch self {
        case .loggedOut: return false
        case .loggedIn: return true
        }
    }

    var token: String? {
        switch self {
        case .loggedOut: return nil
        case let .loggedIn(token): return token
        }
    }
}

let tokenAccessPath = "com.metropolia.soundscape.token"

final class LoginStateService {
    var state: LoginState
    let keychain = KeychainSwift()

    init() {
        self.tokenStorage = keychain.get(tokenAccessPath)
        self.state = LoginState(token: tokenStorage)
    }

    func clear() {
        tokenStorage = nil
    }

    @objc var tokenStorage: String? {
        didSet {
            if let token = tokenStorage {
                keychain.set(token, forKey: tokenAccessPath)
            } else {
                keychain.clear()
            }
            state = LoginState(token: tokenStorage)
        }
    }
}