import Foundation

// MARK: - Screen States

public enum PRReviewScreen: Equatable {
    case modeSelection
    case riskMap
    case sectionList
    case sectionView(Int)
    case summary
    case done
}

// MARK: - Engine

public struct PRReviewEngine {
    public let review: PRReview
    public let riskFiles: [AssessedFile]
    public let config: PRConfig
    public private(set) var state: PRReviewState
    public private(set) var currentScreen: PRReviewScreen
    public internal(set) var selectedIndex: Int

    public init(review: PRReview, quickMode: Bool = false, riskFiles: [AssessedFile] = [], config: PRConfig = .default) {
        self.review = review
        self.riskFiles = riskFiles
        self.config = config
        self.state = PRReviewState(sectionCount: review.sections.count)
        self.selectedIndex = 0

        if quickMode {
            self.currentScreen = .sectionList
        } else if !riskFiles.isEmpty {
            self.currentScreen = .riskMap
        } else {
            self.currentScreen = .modeSelection
        }
    }

    public init(review: PRReview, state: PRReviewState, riskFiles: [AssessedFile] = [], config: PRConfig = .default) {
        self.review = review
        self.riskFiles = riskFiles
        self.config = config
        self.state = state
        self.selectedIndex = state.currentSectionIndex
        self.currentScreen = .sectionList
    }

    // MARK: - Input Handling (raw key — for backward compat)

    public mutating func handle(key: KeyEvent) {
        // Map through key mode, or handle raw for unmapped keys
        if let action = config.keyMode.mapAction(for: key) {
            handle(action: action)
        } else {
            // Direct key handling for keys not in the mode map
            handleRawKey(key)
        }
    }

    // MARK: - Input Handling (logical action)

    public mutating func handle(action: InputAction) {
        switch currentScreen {
        case .modeSelection:
            handleModeSelection(action)
        case .riskMap:
            handleRiskMap(action)
        case .sectionList:
            handleSectionList(action)
        case .sectionView(let idx):
            handleSectionView(action, sectionIndex: idx)
        case .summary:
            handleSummary(action)
        case .done:
            break
        }

        state.currentSectionIndex = selectedIndex
        state.lastUpdatedAt = Date()
    }

    private mutating func handleRawKey(_ key: KeyEvent) {
        // Fallback: arrow keys always work regardless of mode
        switch key {
        case .up:
            handle(action: .prev)
        case .down:
            handle(action: .next)
        case .enter:
            handle(action: .select)
        case .escape:
            handle(action: .back)
        default:
            break
        }
    }

    // MARK: - Mode Selection

    private mutating func handleModeSelection(_ action: InputAction) {
        switch action {
        case .select:
            currentScreen = riskFiles.isEmpty ? .sectionList : .riskMap
        case .back, .quit:
            currentScreen = .done
        default:
            break
        }
    }

    // MARK: - Risk Map

    private mutating func handleRiskMap(_ action: InputAction) {
        switch action {
        case .select:
            currentScreen = .sectionList
        case .back, .quit:
            currentScreen = .done
        default:
            break
        }
    }

    // MARK: - Section List

    private mutating func handleSectionList(_ action: InputAction) {
        let count = review.sections.count
        switch action {
        case .next:
            if selectedIndex < count - 1 { selectedIndex += 1 }
        case .prev:
            if selectedIndex > 0 { selectedIndex -= 1 }
        case .first:
            selectedIndex = 0
        case .last:
            selectedIndex = max(0, count - 1)
        case .select:
            currentScreen = .sectionView(selectedIndex)
        case .summary:
            currentScreen = .summary
        case .back:
            if !riskFiles.isEmpty {
                currentScreen = .riskMap
            } else {
                currentScreen = .done
            }
        case .quit:
            currentScreen = .done
        default:
            break
        }
    }

    // MARK: - Section View

    private mutating func handleSectionView(_ action: InputAction, sectionIndex: Int) {
        switch action {
        case .back:
            currentScreen = .sectionList
        case .approve:
            state.verdicts[sectionIndex] = .approved
            currentScreen = .sectionList
        case .comment:
            state.verdicts[sectionIndex] = .comment
            currentScreen = .sectionList
        case .requestChanges:
            state.verdicts[sectionIndex] = .requestChanges
            currentScreen = .sectionList
        default:
            break
        }
    }

    // MARK: - Summary

    private mutating func handleSummary(_ action: InputAction) {
        switch action {
        case .back:
            currentScreen = .sectionList
        case .quit:
            currentScreen = .done
        default:
            break
        }
    }
}
