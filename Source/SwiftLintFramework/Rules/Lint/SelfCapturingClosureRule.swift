import SwiftSyntax

struct SelfCapturingClosureRule: SwiftSyntaxRule, ConfigurationProviderRule, OptInRule {
    var configuration = SeverityConfiguration(.warning)

    init() {}

    static var description = RuleDescription(
        identifier: "self_capturing_closure",
        name: "Self Capturing Closure",
        description: "Self references in closures should be marked explicitly or should be weak to avoid reference cycles",
        kind: .lint,
        nonTriggeringExamples: [
            Example("""
            [1, 2].map { [self] num in
                self.handle(num)
            }
            """),
            Example("""
            [1, 2].map { [unowned self] num in
                self.handle(num)
            }
            """),
            Example("""
            [1, 2].map { [weak self] num in
                self?.handle(num)
            }
            """)
        ],
        triggeringExamples: [
            Example("""
            [1, 2].map { num in
                ↓self.log(num)
            }
            """),
            Example("""
            [1, 2].map { [self] num1 in
                [1, 2].map { num2 in
                    ↓self.log("\\(num1), \\(num2)")
                }
            }
            """)
        ]
    )

    func makeVisitor(file: SwiftLintFile) -> ViolationsSyntaxVisitor {
        return Visitor(viewMode: .sourceAccurate)
    }
}

private extension SelfCapturingClosureRule {
    final class Visitor: ViolationsSyntaxVisitor {
        override func visitPost(_ node: ClosureExprSyntax) {
            let captureContainsSelf = node.signature?.capture?.items?.contains { item in
                guard let expr = item.expression.as(IdentifierExprSyntax.self) else {
                    return false
                }
                return expr.identifier.tokenKind == .keyword(.Self)
            } ?? false

            // allow explicit capture with "[self]", "[unowned self]" or "[weak self]"
            guard !captureContainsSelf else {
                return
            }

            let foundSelfReferences = SelfReferenceVisitor()
                .walk(tree: node.statements, handler: \.foundSelfReferences)

            guard foundSelfReferences.isNotEmpty else {
                return
            }

            violations.append(node.positionAfterSkippingLeadingTrivia)
        }
    }
}

private final class SelfReferenceVisitor: SyntaxVisitor {
    private(set) var foundSelfReferences: Set<IdentifierExprSyntax> = []

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: CodeBlockSyntax) -> SyntaxVisitorContinueKind {
        // ignore nested closures
        .skipChildren
    }

    override func visitPost(_ node: IdentifierExprSyntax) {
        if node.identifier.tokenKind == .keyword(.Self) {
            foundSelfReferences.insert(node)
        }
    }
}
