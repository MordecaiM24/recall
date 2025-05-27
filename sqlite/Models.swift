import Foundation
import Combine

struct Contact: Identifiable {
    let id: Int32
    let name: String
}

@MainActor
final class ContactModel: ObservableObject {
    @Published private(set) var contacts: [Contact] = []
    private let service: SQLiteService

    init(service: SQLiteService = try! SQLiteService()) {
        self.service = service
        setupDatabase()
        refresh()
    }

    private func setupDatabase() {
        let sql = """
        CREATE TABLE IF NOT EXISTS Contact(
            Id INTEGER PRIMARY KEY AUTOINCREMENT,
            Name TEXT NOT NULL
        );
        """
        try? service.execute(sql)
    }

    func refresh() {
        Task {
            let rows = try? await Task.detached { [service] in
                return try service.findContacts()
            }.value
            if let rows = rows {
                contacts = rows
            }
        }
    }

    func insert(name: String) {
        Task {
            try? await Task.detached { [service, name] in
                try service.insertContact(name: name)
            }.value
            refresh()
        }
    }
}

