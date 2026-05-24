import UIKit

/// Test double for DocumentScannerPresenting. Instead of opening VisionKit,
/// presents a minimal view controller with "Finish" / "Cancel" buttons.
/// "Finish" hands back a deterministic fixture image so UI tests don't
/// depend on a real camera or scanned content.
struct StubDocumentScanner: DocumentScannerPresenting {

    func makeViewController(
        onFinish: @escaping ([UIImage]) -> Void,
        onCancel: @escaping () -> Void
    ) -> UIViewController {
        StubScannerViewController(onFinish: onFinish, onCancel: onCancel)
    }
}

private final class StubScannerViewController: UIViewController {
    let onFinish: ([UIImage]) -> Void
    let onCancel: () -> Void

    init(onFinish: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
        self.onFinish = onFinish
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let finishButton = UIButton(type: .system)
        finishButton.setTitle("Finish", for: .normal)
        finishButton.titleLabel?.font = .systemFont(ofSize: 24, weight: .semibold)
        finishButton.accessibilityIdentifier = "StubScanner.Finish"
        finishButton.addAction(UIAction { [weak self] _ in
            self?.onFinish([Self.fixtureImage()])
        }, for: .touchUpInside)

        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.accessibilityIdentifier = "StubScanner.Cancel"
        cancelButton.addAction(UIAction { [weak self] _ in
            self?.onCancel()
        }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [finishButton, cancelButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    /// A deterministic 612×792 (US Letter) page with a unique marker
    /// string so UI tests can verify it round-trips.
    static func fixtureImage() -> UIImage {
        let size = CGSize(width: 612, height: 792)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            let text = "UITest fixture page"
            (text as NSString).draw(
                at: CGPoint(x: 40, y: 60),
                withAttributes: [
                    .font: UIFont.boldSystemFont(ofSize: 48),
                    .foregroundColor: UIColor.black
                ]
            )
        }
    }
}
