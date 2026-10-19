import Foundation
import SwiftData

@Model
final class ProductionTeam {
    var remoteID: UUID?
    var name: String
    var teamDescription: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \TeamMember.team)
    var members: [TeamMember]
    @Relationship(deleteRule: .cascade, inverse: \TeamMessage.team)
    var messages: [TeamMessage]

    init(name: String, teamDescription: String = "") {
        self.name = name
        self.teamDescription = teamDescription
        self.createdAt = .now
        self.members = []
        self.messages = []
    }
}

@Model
final class TeamMember {
    var remoteID: UUID?
    var name: String
    var email: String?
    var phoneNumber: String?
    var role: String
    var releasedBudget: Double = 0
    var team: ProductionTeam?
    @Relationship(deleteRule: .cascade, inverse: \TeamExpense.producer)
    var expenses: [TeamExpense] = []

    init(name: String, email: String = "", phoneNumber: String? = nil, role: String, team: ProductionTeam? = nil, releasedBudget: Double = 0) {
        self.name = name
        self.email = email
        self.phoneNumber = phoneNumber
        self.role = role
        self.team = team
        self.releasedBudget = releasedBudget
        self.expenses = []
    }
}

@Model
final class TeamExpense {
    var remoteID: UUID?
    var descriptionText: String
    var amount: Double
    var createdAt: Date
    var producerName: String
    var producerEmail: String
    var producer: TeamMember?
    @Relationship(deleteRule: .cascade, inverse: \ExpenseReceipt.expense)
    var receipts: [ExpenseReceipt] = []

    init(descriptionText: String, amount: Double, producerName: String, producerEmail: String, producer: TeamMember? = nil) {
        self.descriptionText = descriptionText
        self.amount = amount
        self.createdAt = .now
        self.producerName = producerName
        self.producerEmail = producerEmail
        self.producer = producer
        self.receipts = []
    }
}

@Model
final class ExpenseReceipt {
    var remotePath: String?
    @Attribute(.externalStorage) var imageData: Data
    var fileName: String
    var expense: TeamExpense?

    init(imageData: Data, fileName: String, expense: TeamExpense? = nil) {
        self.imageData = imageData
        self.fileName = fileName
        self.expense = expense
    }
}

@Model
final class TeamMessage {
    var remoteID: UUID?
    var text: String
    var senderName: String
    var sentAt: Date
    var team: ProductionTeam?

    init(text: String, senderName: String, sentAt: Date = .now, team: ProductionTeam? = nil) {
        self.text = text
        self.senderName = senderName
        self.sentAt = sentAt
        self.team = team
    }
}
