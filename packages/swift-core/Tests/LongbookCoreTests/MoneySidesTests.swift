import XCTest
@testable import LongbookCore

/// From and To for each kind of money, read from the file as it stands.
final class MoneySidesTests: XCTestCase {
    private let book = MoneySides.Book(Vault(
        app: "longbook", subscriptions: [],
        familyMembers: [
            FamilyMember(id: "m-jo", name: "Jordan Lee", nameKey: "jordan lee"),
            FamilyMember(id: "m-maria", name: "Maria Gomez", nameKey: "maria gomez"),
            FamilyMember(id: "m-sam", name: "Sam", nameKey: "sam"),
        ],
        paymentMethods: [
            PaymentMethod(id: "a-chase", name: "Chase Bank", nameKey: "chase bank", familyMemberId: "m-jo"),
            PaymentMethod(id: "a-ally", name: "Ally Bank", nameKey: "ally bank", familyMemberId: "m-sam"),
            PaymentMethod(id: "a-loose", name: "Loose card", nameKey: "loose card"),
        ]
    ))

    private func sub(_ name: String, account: String? = "a-chase", member: String? = nil, direction: String? = nil,
                     counterpart: String? = nil, counterpartName: String? = nil) -> Subscription {
        var details: Details = [:]
        if let counterpart { details[CounterpartAccounts.idKey] = .string(counterpart) }
        if let counterpartName { details[CounterpartAccounts.nameKey] = .string(counterpartName) }
        return Subscription(id: "s", name: name, amount: 10, currency: "USD", billingCycle: .once,
                            familyMemberId: member, paymentMethodId: account, status: .active,
                            details: details, direction: direction)
    }

    func testMoneyOutRunsFromTheAccountsOwnerToTheCommitmentsPerson() {
        let sides = MoneySides.of(sub("House cleaning", member: "m-maria", counterpart: "a-ally"), in: book)
        XCTAssertEqual(sides.from, .init(accountId: "a-chase", account: "Chase Bank", personId: "m-jo", person: "Jordan Lee"))
        XCTAssertEqual(sides.to, .init(accountId: "a-ally", account: "Ally Bank", personId: "m-maria", person: "Maria Gomez"))
    }

    func testAPersonNamesOnlySomeoneInPeople() {
        let out = MoneySides.of(sub("Corner shop", member: "m-not-in-people"), in: book)
        XCTAssertNil(out.to.person)
        XCTAssertNil(out.to.personId)
        // A person a Proposal adds is in the file's People, so the book reads them.
        let adding = MoneySides.Book(Vault(
            app: "longbook", subscriptions: [],
            familyMembers: [FamilyMember(id: "m-nina", name: "Nina Patel", nameKey: "nina patel")],
            paymentMethods: []
        ))
        XCTAssertEqual(MoneySides.of(sub("Piano lessons", account: nil, member: "m-nina"), in: adding).to.person, "Nina Patel")
    }

    func testABusinessIsNeverAPerson() {
        let out = MoneySides.of(sub("Payment to Whole Foods"), in: book)
        XCTAssertNil(out.to.person)
        XCTAssertNil(out.to.personId)
        let earned = MoneySides.of(sub("Payment from Acme Payroll", direction: "in"), in: book)
        XCTAssertNil(earned.from.person)
        XCTAssertNil(earned.from.personId)
    }

    func testMoneyInLandsWithTheStatementHolder() {
        let sides = MoneySides.of(sub("Rent from tenant", member: "m-maria", direction: "in", counterpart: "a-ally"), in: book)
        XCTAssertEqual(sides.from.account, "Ally Bank")
        XCTAssertEqual(sides.from.person, "Maria Gomez")
        XCTAssertEqual(sides.to.account, "Chase Bank")
        XCTAssertEqual(sides.to.person, "Jordan Lee")
    }

    func testATransferNamesEachAccountsOwnerAndNeverTheCommitmentsPerson() {
        let sides = MoneySides.of(sub("To savings", member: "m-maria", direction: "transfer", counterpart: "a-ally"), in: book)
        XCTAssertEqual(sides.from.person, "Jordan Lee")
        XCTAssertEqual(sides.to.account, "Ally Bank")
        XCTAssertEqual(sides.to.person, "Sam")
        XCTAssertEqual(sides.personIds, ["m-jo", "m-sam"])
        XCTAssertEqual(sides.accountIds, ["a-chase", "a-ally"])
    }

    func testATransferWithNoOtherAccountNamesNobodyThere() {
        let sides = MoneySides.of(sub("Amex card bill", direction: "transfer"), in: book)
        XCTAssertEqual(sides.to, .init())
    }

    func testAnAccountWithNoOwnerLeavesItsSideEmpty() {
        let sides = MoneySides.of(sub("Payment to Shell", account: "a-loose"), in: book)
        XCTAssertNil(sides.from.person)
        XCTAssertEqual(sides.from.account, "Loose card")
    }

    func testACounterpartNamedByAStatementIsMatchedOrKeptAsItsName() {
        let matched = MoneySides.of(sub("To Ally", direction: "transfer", counterpartName: "ally bank"), in: book)
        XCTAssertEqual(matched.to.accountId, "a-ally")
        XCTAssertEqual(matched.to.person, "Sam")
        let loose = MoneySides.of(sub("To Axis", direction: "transfer", counterpartName: "Axis savings"), in: book)
        XCTAssertEqual(loose.to.account, "Axis savings")
        XCTAssertNil(loose.to.accountId)
    }

    func testOnePersonOnBothSidesCountsOnce() {
        let sides = MoneySides.of(sub("Self pay", member: "m-jo"), in: book)
        XCTAssertEqual(sides.personIds, ["m-jo"])
    }
}
