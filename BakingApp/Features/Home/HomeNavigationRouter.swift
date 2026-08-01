import Foundation
import SwiftUI
import UIKit

/// Single source of truth for Home push/pop navigation.
@MainActor
final class HomeNavigationRouter: ObservableObject {
    @Published private(set) var path: [HomeNavigationRoute] = []

    var pathCount: Int { path.count }
    var canPop: Bool { !path.isEmpty }
    var topRoute: HomeNavigationRoute? { path.last }

    func push(_ route: HomeNavigationRoute, screen: String) {
        // Prevent accidental duplicate top routes from double taps.
        if path.last == route {
            HomeNavigationDebug.log(
                screen: screen,
                route: String(describing: route),
                pathCount: path.count,
                backTapReceived: false,
                resultingPathCount: path.count,
                note: "ignored_duplicate_push"
            )
            return
        }
        path.append(route)
        HomeNavigationDebug.log(
            screen: screen,
            route: String(describing: route),
            pathCount: path.count,
            backTapReceived: false,
            resultingPathCount: path.count,
            note: "push"
        )
    }

    /// Removes exactly one route. No-op when already at root.
    func pop(screen: String) {
        let before = path.count
        guard canPop else {
            HomeNavigationDebug.log(
                screen: screen,
                route: String(describing: topRoute),
                pathCount: before,
                backTapReceived: true,
                resultingPathCount: before,
                note: "pop_ignored_empty"
            )
            return
        }
        let removed = path.removeLast()
        HomeNavigationDebug.log(
            screen: screen,
            route: String(describing: removed),
            pathCount: before,
            backTapReceived: true,
            resultingPathCount: path.count,
            note: "pop"
        )
    }

    func popToRoot(screen: String) {
        let before = path.count
        path.removeAll()
        HomeNavigationDebug.log(
            screen: screen,
            route: "root",
            pathCount: before,
            backTapReceived: false,
            resultingPathCount: 0,
            note: "pop_to_root"
        )
    }

    /// Binding used by `NavigationStack(path:)`.
    var pathBinding: Binding<[HomeNavigationRoute]> {
        Binding(
            get: { self.path },
            set: { newValue in
                let before = self.path.count
                self.path = newValue
                if newValue.count < before {
                    HomeNavigationDebug.log(
                        screen: "NavigationStack",
                        route: String(describing: newValue.last),
                        pathCount: before,
                        backTapReceived: false,
                        resultingPathCount: newValue.count,
                        note: "path_binding_set_pop"
                    )
                } else if newValue.count > before {
                    HomeNavigationDebug.log(
                        screen: "NavigationStack",
                        route: String(describing: newValue.last),
                        pathCount: before,
                        backTapReceived: false,
                        resultingPathCount: newValue.count,
                        note: "path_binding_set_push"
                    )
                }
            }
        )
    }
}

enum HomeNavigationDebug {
    static func log(
        screen: String,
        route: String?,
        pathCount: Int,
        backTapReceived: Bool,
        resultingPathCount: Int,
        note: String
    ) {
        #if DEBUG
        print(
            "[HomeNav] screen=\(screen) route=\(route ?? "nil") pathCount=\(pathCount) "
                + "backTapReceived=\(backTapReceived) resultingPathCount=\(resultingPathCount) note=\(note)"
        )
        #endif
    }

    static func stackCountMarker() -> String {
        #if DEBUG
        return "home_nav_stack_owner=1"
        #else
        return ""
        #endif
    }
}

/// Explicit back control — sole back tap mechanism for pushed Home routes.
/// Native system back is hidden so there is never a competing visible control.
struct HomeBackToolbarModifier: ViewModifier {
    @ObservedObject var router: HomeNavigationRouter
    let screen: String
    let accessibilityIdentifier: String

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        router.pop(screen: screen)
                    } label: {
                        // Explicit ≥44×44 hit box matching the large visible control users tap.
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.backward")
                                .font(.body.weight(.semibold))
                            Text("Back")
                                .font(.body)
                        }
                        .foregroundStyle(Color.accentColor)
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!router.canPop)
                    .accessibilityLabel("Back")
                    .accessibilityIdentifier(accessibilityIdentifier)
                }
            }
            // Deterministic edge-swipe pop through the same router (not a second navigation owner).
            .simultaneousGesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        let fromLeadingEdge = value.startLocation.x < 28
                        let swipedRight = value.translation.width > 80
                        if fromLeadingEdge && swipedRight && router.canPop {
                            router.pop(screen: screen)
                        }
                    }
            )
            .background(HomeInteractivePopGestureEnabler())
    }
}

extension View {
    func homeBackToolbar(
        router: HomeNavigationRouter,
        screen: String,
        accessibilityIdentifier: String
    ) -> some View {
        modifier(
            HomeBackToolbarModifier(
                router: router,
                screen: screen,
                accessibilityIdentifier: accessibilityIdentifier
            )
        )
    }
}

/// Keeps edge-swipe pop available while the system back button is hidden.
/// Swipe updates `NavigationStack` path via `pathBinding` (same router source of truth).
private struct HomeInteractivePopGestureEnabler: UIViewControllerRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        Controller(coordinator: context.coordinator)
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        (uiViewController as? Controller)?.enablePopGestureIfPossible()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var navigationController: UINavigationController?

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }

    final class Controller: UIViewController {
        private let coordinator: Coordinator

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            enablePopGestureIfPossible()
        }

        func enablePopGestureIfPossible() {
            guard let nav = navigationController else { return }
            coordinator.navigationController = nav
            guard let pop = nav.interactivePopGestureRecognizer else { return }
            pop.isEnabled = nav.viewControllers.count > 1
            pop.delegate = coordinator
        }
    }
}
