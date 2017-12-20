import Foundation

public enum CollectionViewCellSwipeType {
    case primary, secondary, none
}

enum CollectionViewCellState {
    case idle, open
}

public class CollectionViewEditController: NSObject, UIGestureRecognizerDelegate, ActionDelegate {
    
    let collectionView: UICollectionView
    
    struct SwipeInfo {
        let translation: CGFloat
        let velocity: CGFloat
    }
    var swipeInfoByIndexPath: [IndexPath: SwipeInfo] = [:]
    
    var activeCell: SwipeableCell? {
        guard let indexPath = activeIndexPath else {
            return nil
        }
        return collectionView.cellForItem(at: indexPath) as? SwipeableCell
    }

    public var isActive: Bool {
        return activeIndexPath != nil
    }
    // disabled
    var activeIndexPath: IndexPath? {
        didSet {
            if activeIndexPath != nil {
                batchEditingState = .inactive
            } else {
                batchEditingState = .none
            }
        }
    }
    var isRTL: Bool = false
    var initialSwipeTranslation: CGFloat = 0
    let maxExtension: CGFloat = 10
    
    let panGestureRecognizer: UIPanGestureRecognizer
    let longPressGestureRecognizer: UILongPressGestureRecognizer
    
    public init(collectionView: UICollectionView) {
        self.collectionView = collectionView
        panGestureRecognizer = UIPanGestureRecognizer()
        longPressGestureRecognizer = UILongPressGestureRecognizer()
        super.init()
        panGestureRecognizer.addTarget(self, action: #selector(handlePanGesture))
        longPressGestureRecognizer.addTarget(self, action: #selector(handleLongPressGesture))
        if let gestureRecognizers = self.collectionView.gestureRecognizers {
            var otherGestureRecognizer: UIGestureRecognizer
            for gestureRecognizer in gestureRecognizers {
                otherGestureRecognizer = gestureRecognizer is UIPanGestureRecognizer ? panGestureRecognizer : longPressGestureRecognizer
                gestureRecognizer.require(toFail: otherGestureRecognizer)
            }

        }
        
        panGestureRecognizer.delegate = self
        self.collectionView.addGestureRecognizer(panGestureRecognizer)
        
        longPressGestureRecognizer.delegate = self
        longPressGestureRecognizer.minimumPressDuration = 0.05
        longPressGestureRecognizer.require(toFail: panGestureRecognizer)
        self.collectionView.addGestureRecognizer(longPressGestureRecognizer)
        
    }
    
    public func swipeTranslationForItem(at indexPath: IndexPath) -> CGFloat? {
        return swipeInfoByIndexPath[indexPath]?.translation
    }
    
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGestureRecognizer {
            return panGestureRecognizerShouldBegin(panGestureRecognizer)
        }
        
        if gestureRecognizer === longPressGestureRecognizer  {
            return longPressGestureRecognizerShouldBegin(longPressGestureRecognizer)
        }
        
        return false
    }
    
    public weak var delegate: ActionDelegate?
    
    public func didPerformAction(_ action: Action) -> Bool {
        guard action.indexPath == activeIndexPath else {
            return self.delegate?.didPerformAction(action) ?? false
        }
        let activatedAction = action.type == .delete ? action : nil
        closeActionPane(with: activatedAction) { (finished) in
            let _ = self.delegate?.didPerformAction(action)
        }
        return true
    }
    
    func panGestureRecognizerShouldBegin(_ gestureRecognizer: UIPanGestureRecognizer) -> Bool {
        var shouldBegin = false
        defer {
            if !shouldBegin {
                closeActionPane()
            }
        }
        guard let delegate = delegate else {
            return shouldBegin
        }
        
        let position = gestureRecognizer.location(in: collectionView)
        
        guard let indexPath = collectionView.indexPathForItem(at: position) else {
            return shouldBegin
        }

        let velocity = gestureRecognizer.velocity(in: collectionView)
        
        // Begin only if there's enough x velocity.
        if fabs(velocity.y) >= fabs(velocity.x) {
            return shouldBegin
        }
        
        defer {
            if let indexPath = activeIndexPath {
                initialSwipeTranslation = swipeInfoByIndexPath[indexPath]?.translation ?? 0
            }
        }

        isRTL = collectionView.effectiveUserInterfaceLayoutDirection == .rightToLeft
        let isOpenSwipe = isRTL ? velocity.x > 0 : velocity.x < 0

        if !isOpenSwipe { // only allow closing swipes on active cells
            shouldBegin = indexPath == activeIndexPath
            return shouldBegin
        }
        
        if activeIndexPath != nil && activeIndexPath != indexPath {
            closeActionPane()
        }
        
        guard activeIndexPath == nil else {
            shouldBegin = true
            return shouldBegin
        }

        activeIndexPath = indexPath
        guard let cell = activeCell, cell.actions.count > 0 else {
            activeIndexPath = nil
            return shouldBegin
        }
        
        shouldBegin = true
        return shouldBegin
    }
    
    func longPressGestureRecognizerShouldBegin(_ gestureRecognizer: UILongPressGestureRecognizer) -> Bool {
        guard let cell = activeCell else {
            return false
        }
        
        // Don't allow the cancel gesture to recognize if any of the touches are within the actions view.
        let numberOfTouches = gestureRecognizer.numberOfTouches
        
        for touchIndex in 0..<numberOfTouches {
            let touchLocation = gestureRecognizer.location(ofTouch: touchIndex, in: cell.actionsView)
            let touchedActionsView = cell.actionsView.bounds.contains(touchLocation)
            return !touchedActionsView
        }
        
        return true
    }
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        
        if gestureRecognizer is UILongPressGestureRecognizer {
            return true
        }
        
        if gestureRecognizer is UIPanGestureRecognizer{
            return otherGestureRecognizer is UILongPressGestureRecognizer
        }
        
        return false
    }
    
    @objc func handlePanGesture(_ sender: UIPanGestureRecognizer) {
        guard let indexPath = activeIndexPath, let cell = activeCell else {
            return
        }
        cell.actionsView.delegate = self
        let deltaX = sender.translation(in: collectionView).x
        let velocityX = sender.velocity(in: collectionView).x
        var swipeTranslation = deltaX + initialSwipeTranslation
        let normalizedSwipeTranslation = isRTL ? swipeTranslation : -swipeTranslation
        let normalizedMaxSwipeTranslation = abs(cell.swipeTranslationWhenOpen)
        switch (sender.state) {
        case .began:
            cell.swipeState = .swiping
            fallthrough
        case .changed:
            if normalizedSwipeTranslation < 0 {
                let normalizedSqrt = maxExtension * log(abs(normalizedSwipeTranslation))
                swipeTranslation = isRTL ? 0 - normalizedSqrt : normalizedSqrt
            }
            if normalizedSwipeTranslation > normalizedMaxSwipeTranslation {
                let maxWidth = normalizedMaxSwipeTranslation
                let delta = normalizedSwipeTranslation - maxWidth
                swipeTranslation = isRTL ? maxWidth + (maxExtension * log(delta)) : 0 - maxWidth - (maxExtension * log(delta))
            }
            cell.swipeTranslation = swipeTranslation
            swipeInfoByIndexPath[indexPath] = SwipeInfo(translation: swipeTranslation, velocity: velocityX)
        case .cancelled:
            fallthrough
        case .failed:
            fallthrough
        case .ended:
            let isOpen: Bool
            let velocityAdjustment = 0.3 * velocityX
            if isRTL {
                isOpen = swipeTranslation + velocityAdjustment > 0.5 * cell.swipeTranslationWhenOpen
            } else {
                isOpen = swipeTranslation + velocityAdjustment < 0.5 * cell.swipeTranslationWhenOpen
            }
            if isOpen {
                openActionPane()
            } else {
                closeActionPane()
            }
            fallthrough
        default:
            break
        }
    }
    
    @objc func handleLongPressGesture(_ sender: UILongPressGestureRecognizer) {
        guard activeIndexPath != nil else {
            return
        }
        
        switch (sender.state) {
        case .ended:
            closeActionPane()
        default:
            break
        }
    }
    
    var areSwipeActionsDisabled: Bool = false {
        didSet {
            longPressGestureRecognizer.isEnabled = !areSwipeActionsDisabled
            panGestureRecognizer.isEnabled = !areSwipeActionsDisabled
        }
    }
    
    // MARK: - States
    
    func openActionPane(_ completion: @escaping (Bool) -> Void = {_ in }) {
        collectionView.allowsSelection = false
        guard let cell = activeCell, let indexPath = activeIndexPath else {
            completion(false)
            return
        }
        let targetTranslation =  cell.swipeTranslationWhenOpen
        let velocity = swipeInfoByIndexPath[indexPath]?.velocity ?? 0
        swipeInfoByIndexPath[indexPath] = SwipeInfo(translation: targetTranslation, velocity: velocity)
        cell.swipeState = .open
        animateActionPane(of: cell, to: targetTranslation, with: velocity, completion: completion)
    }
    
    func closeActionPane(with expandedAction: Action? = nil, _ completion: @escaping (Bool) -> Void = {_ in }) {
        collectionView.allowsSelection = true
        guard let cell = activeCell, let indexPath = activeIndexPath else {
            completion(false)
            return
        }
        activeIndexPath = nil
        let velocity = swipeInfoByIndexPath[indexPath]?.velocity ?? 0
        swipeInfoByIndexPath[indexPath] = nil
        if let expandedAction = expandedAction {
            let translation = isRTL ? cell.bounds.width : 0 - cell.bounds.width
            animateActionPane(of: cell, to: translation, with: velocity, expandedAction: expandedAction, completion: { (finished) in
                //don't set isSwiping to false so that the expanded action stays visible through the fade
                completion(finished)
            })
        } else {
            animateActionPane(of: cell, to: 0, with: velocity, completion: { (finished: Bool) in
                cell.swipeState = self.activeIndexPath == indexPath ? .swiping : .closed
                completion(finished)
            })
        }
    }

    func animateActionPane(of cell: SwipeableCell, to targetTranslation: CGFloat, with swipeVelocity: CGFloat, expandedAction: Action? = nil, completion: @escaping (Bool) -> Void = {_ in }) {
         if let action = expandedAction {
            UIView.animate(withDuration: 0.3, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState], animations: {
                cell.actionsView.expand(action)
                cell.swipeTranslation = targetTranslation
                cell.layoutIfNeeded()
            }, completion: completion)
            return
        }
        let initialSwipeTranslation = cell.swipeTranslation
        let animationTranslation = targetTranslation - initialSwipeTranslation
        let animationDuration: TimeInterval = 0.3
        let distanceInOneSecond = animationTranslation / CGFloat(animationDuration)
        let unitSpeed = distanceInOneSecond == 0 ? 0 : swipeVelocity / distanceInOneSecond
        UIView.animate(withDuration: animationDuration, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: unitSpeed, options: [.allowUserInteraction, .beginFromCurrentState], animations: {
            cell.swipeTranslation = targetTranslation
            cell.layoutIfNeeded()
        }, completion: completion)
    }
    
    // MARK: - Batch editing
    
    public weak var navigationDelegate: BatchEditNavigationDelegate? {
        didSet {
            batchEditingState = .none
        }
    }
    
    fileprivate var editableCells: [BatchEditableCell] {
        guard let editableCells = collectionView.visibleCells as? [BatchEditableCell] else {
            return []
        }
        return editableCells
    }
    
    fileprivate var batchEditingState: BatchEditingState = .none {
        didSet {
            var barButtonSystemItem: UIBarButtonSystemItem = UIBarButtonSystemItem.edit
            var enabled = true
            var tag = 0
            
            defer {
                let button = UIBarButtonItem(barButtonSystemItem: barButtonSystemItem, target: self, action: #selector(batchEdit(_:)))
                button.tag = tag
                button.isEnabled = enabled
                navigationDelegate?.changeRightNavButton(to: button)
            }
            
            guard !isCollectionViewEmpty else {
                isBatchEditToolbarVisible = false
                enabled = false
                return
            }

            switch batchEditingState {
            case .inactive:
                barButtonSystemItem = .done
                tag = -1
            case .none:
                break
            case .cancelled:
                animateBatchEditPane(for: batchEditingState)
            case .open:
                barButtonSystemItem = UIBarButtonSystemItem.cancel
                tag = 1
                animateBatchEditPane(for: batchEditingState)
            }
        }
    }
    
    fileprivate func animateBatchEditPane(for state: BatchEditingState) {
        let willOpen = state == .open
        areSwipeActionsDisabled = willOpen
        collectionView.allowsMultipleSelection = willOpen
        isBatchEditToolbarVisible = false
        for cell in editableCells {
            let targetTranslation = (willOpen ? cell.batchEditSelectView?.fixedWidth : 0) ?? 0
            UIView.animate(withDuration: 0.3, delay: 0.1, options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseInOut], animations: {
                cell.batchEditingTranslation = targetTranslation
                cell.layoutIfNeeded()
            })
        }
        if !willOpen {
            selectedIndexPaths.forEach({ collectionView.deselectItem(at: $0, animated: true) })
        }
    }
    
    @objc public func close() {
        batchEditingState = .cancelled
        closeActionPane()
    }
    
    public var isCollectionViewEmpty: Bool = false {
        didSet {
            batchEditingState = .none
            navigationDelegate?.emptyStateDidChange(isCollectionViewEmpty)
        }
    }
    
    @objc fileprivate func batchEdit(_ sender: UIBarButtonItem) {
        switch sender.tag {
        case -1:
            closeActionPane()
            batchEditingState = .none
        case 0:
            batchEditingState = .open
        case 1:
            batchEditingState = .cancelled
        default:
            return
        }
    }
    
    public var isClosed: Bool {
        let isClosed = batchEditingState != .open
        if !isClosed {
            isBatchEditToolbarVisible = !selectedIndexPaths.isEmpty
        }
        return isClosed
    }
    
    fileprivate var selectedIndexPaths: [IndexPath] {
        return collectionView.indexPathsForSelectedItems ?? []
    }
    
    fileprivate var isBatchEditToolbarVisible: Bool = false {
        didSet {
            guard collectionView.window != nil else {
                return
            }
            self.navigationDelegate?.createBatchEditToolbar(with: self.batchEditToolbarItems, add: self.isBatchEditToolbarVisible)
            self.navigationDelegate?.didSetIsBatchEditToolbarVisible(self.isBatchEditToolbarVisible)
        }
    }
    
    fileprivate var batchEditToolbarActions: [BatchEditToolbarAction] {
        guard let delegate = delegate, let actions = delegate.availableBatchEditToolbarActions else {
            return []
        }
        return actions
    }
    
    @objc public func didPerformBatchEditToolbarAction(with sender: UIBarButtonItem) {
        let didPerformAction = delegate?.didPerformBatchEditToolbarAction?(batchEditToolbarActions[sender.tag]) ?? false
        if didPerformAction {
            batchEditingState = .cancelled
        }
    }
    
    fileprivate lazy var batchEditToolbarItems: [UIBarButtonItem] = {
        
        var buttons: [UIBarButtonItem] = []
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        
        for (index, action) in batchEditToolbarActions.enumerated() {
            if index != 0 {
                buttons.append(flexibleSpace)
            }
            let button = action.button
            button.target = self
            button.action = #selector(didPerformBatchEditToolbarAction(with:))
            button.tag = index
            buttons.append(button)
            if action.type == BatchEditToolbarActionType.update {
                button.isEnabled = false
            }
        }
        
        return buttons
    }()
    
}
