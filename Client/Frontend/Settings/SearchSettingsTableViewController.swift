/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared

private let log = Logger.browserLogger

// MARK: - SearchEnginePickerDelegate

protocol SearchEnginePickerDelegate: class {
    func searchEnginePicker(_ searchEnginePicker: SearchEnginePicker?,
                            didSelectSearchEngine engine: OpenSearchEngine?, forType: DefaultEngineType?)
}

// MARK: - SearchSettingsTableViewController

class SearchSettingsTableViewController: UITableViewController {
    
    // MARK: Design
    
    struct Design {
        static let iconSize = CGSize(
            width: OpenSearchEngine.preferredIconSize,
            height: OpenSearchEngine.preferredIconSize)
        
        static let headerHeight: CGFloat = 44
    }
    
    // MARK: Constants
    
    struct Constants {
        static let sectionHeaderIdentifier = "sectionHeaderIdentifier"
        static let customEngineRowIdentifier = "customEngineRowIdentifier"
        static let searchEngineRowIdentifier = "searchEngineRowIdentifier"
        static let quickEngineRowIdentifier = "quickEngineRowIdentifier"
    }
    
    // MARK: Section
    
    enum Section: Int, CaseIterable {
        case current
        case quickSearch
    }
    
    // MARK: CurrentEngineType
    
    enum CurrentEngineType: Int, CaseIterable {
        case standard
        case `private`
        case suggestions
    }
    
    private var model: SearchEngines
    private var showDeletion = false
    
    private var searchPickerEngines: [OpenSearchEngine] {
        let orderedEngines = model.orderedEngines.sorted { $0.shortName < $1.shortName }
        
        guard let priorityEngine = InitialSearchEngines().priorityEngine?.rawValue else {
            return orderedEngines
        }
        
        return orderedEngines.sorted { engine, _ in
            engine.engineID == priorityEngine
        }
    }
    
    // MARK: Lifecycle
    
    init(model: SearchEngines) {
        self.model = model
        
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = Strings.searchSettingNavTitle

        tableView.do {
            // To allow re-ordering the list of search engines at all times.
            $0.isEditing = true
            // So that we push the default search engine controller on selection.
            $0.allowsSelectionDuringEditing = true

            $0.register(SettingsTableSectionHeaderFooterView.self, forHeaderFooterViewReuseIdentifier: Constants.sectionHeaderIdentifier)
            $0.register(UITableViewCell.self, forCellReuseIdentifier: Constants.customEngineRowIdentifier)
            $0.register(UITableViewCell.self, forCellReuseIdentifier: Constants.searchEngineRowIdentifier)
            $0.register(UITableViewCell.self, forCellReuseIdentifier: Constants.quickEngineRowIdentifier)
        }

        // Insert Done button if being presented outside of the Settings Nav stack
        if !(navigationController is SettingsNavigationController) {
            navigationItem.leftBarButtonItem =
                UIBarButtonItem(title: Strings.settingsSearchDoneButton, style: .done, target: self, action: #selector(dismissAnimated))
        }

        let footer = SettingsTableSectionHeaderFooterView(frame: CGRect(width: tableView.bounds.width, height: Design.headerHeight))
        tableView.tableFooterView = footer
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        tableView.reloadData()
    }
    
    // MARK: TableViewDataSource - TableViewDelegate

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell: UITableViewCell?
        var engine: OpenSearchEngine?

        if indexPath.section == Section.current.rawValue {
            switch indexPath.item {
                case CurrentEngineType.standard.rawValue:
                    engine = model.defaultEngine(forType: .standard)
                    cell = configureSearchEngineCell(type: .standard, engineName: engine?.displayName)
                case CurrentEngineType.private.rawValue:
                    engine = model.defaultEngine(forType: .privateMode)
                    cell = configureSearchEngineCell(type: .privateMode, engineName: engine?.displayName)
                case CurrentEngineType.suggestions.rawValue:
                    let toggle = UISwitch().then {
                        $0.addTarget(self, action: #selector(didToggleSearchSuggestions), for: .valueChanged)
                        $0.isOn = model.shouldShowSearchSuggestions
                    }
                    
                    cell = tableView.dequeueReusableCell(withIdentifier: Constants.searchEngineRowIdentifier, for: indexPath).then {
                        $0.textLabel?.text = Strings.searchSettingSuggestionCellTitle
                        $0.editingAccessoryView = toggle
                        $0.selectionStyle = .none
                    }
                default:
                    // Should not happen.
                    break
            }
        } else {
            // The default engine is not a quick search engine.
            let index = indexPath.item + 1
            
            // Add custom engine
            if index == model.orderedEngines.count {
                cell = tableView.dequeueReusableCell(withIdentifier: Constants.customEngineRowIdentifier, for: indexPath).then {
                    $0.textLabel?.text = Strings.searchSettingAddCustomEngineCellTitle
                    $0.editingAccessoryType = .disclosureIndicator
                }
            } else {
                engine = model.orderedEngines[index]
                
                let toggle = UISwitch().then {
                    // This is an easy way to get from the toggle control to the corresponding index.
                    $0.tag = index
                    $0.addTarget(self, action: #selector(didToggleEngine), for: .valueChanged)
                    if let searchEngine = engine {
                        $0.isOn = model.isEngineEnabled(searchEngine)
                    }
                }
                
                cell = tableView.dequeueReusableCell(withIdentifier: Constants.quickEngineRowIdentifier, for: indexPath).then {
                    $0.showsReorderControl = true
                    $0.editingAccessoryView = toggle
                    $0.textLabel?.text = engine?.displayName
                    $0.textLabel?.adjustsFontSizeToFitWidth = true
                    $0.textLabel?.minimumScaleFactor = 0.5
                    $0.imageView?.image = engine?.image.createScaled(Design.iconSize)
                    $0.imageView?.layer.cornerRadius = 4
                    $0.imageView?.layer.masksToBounds = true
                    $0.selectionStyle = .none
                }
            }
        }

        guard let searchEngineCell = cell else { return UITableViewCell() }
        
        // So that the seperator line goes all the way to the left edge.
        searchEngineCell.separatorInset = .zero

        return searchEngineCell
    }
    
    private func configureSearchEngineCell(type: DefaultEngineType, engineName: String?) -> UITableViewCell {
        guard let searchEngineName = engineName else { return UITableViewCell() }

        var text: String
        
        switch type {
        case .standard:
            text = Strings.standardTabSearch
        case .privateMode:
            text = Strings.privateTabSearch
        }
        
        let cell = UITableViewCell(style: .value1, reuseIdentifier: Constants.searchEngineRowIdentifier).then {
            $0.editingAccessoryType = .disclosureIndicator
            $0.accessibilityLabel = text
            $0.textLabel?.text = text
            $0.accessibilityValue = searchEngineName
            $0.detailTextLabel?.text = searchEngineName
        }
        
        return cell
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == Section.current.rawValue {
            return CurrentEngineType.allCases.count
        } else {
            // The first engine -- the default engine -- is not shown in the quick search engine list.
            // But the option to add Custom Engine is.
            return model.orderedEngines.count
        }
    }

    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        if indexPath.section == Section.current.rawValue && indexPath.item == CurrentEngineType.standard.rawValue {
            let searchEnginePicker = SearchEnginePicker(type: .standard).then {
                // Order alphabetically, so that picker is always consistently ordered.
                // Every engine is a valid choice for the default engine, even the current default engine.
                $0.engines = searchPickerEngines
                $0.delegate = self
                $0.selectedSearchEngineName = model.defaultEngine(forType: .standard).shortName
            }
            
            navigationController?.pushViewController(searchEnginePicker, animated: true)
        } else if indexPath.section == Section.current.rawValue && indexPath.item == CurrentEngineType.private.rawValue {
            let searchEnginePicker = SearchEnginePicker(type: .privateMode).then {
                // Order alphabetically, so that picker is always consistently ordered.
                // Every engine is a valid choice for the default engine, even the current default engine.
                $0.engines = searchPickerEngines
                $0.delegate = self
                $0.selectedSearchEngineName = model.defaultEngine(forType: .privateMode).shortName
            }
            
            navigationController?.pushViewController(searchEnginePicker, animated: true)
        } else if indexPath.section == Section.quickSearch.rawValue && indexPath.item == model.orderedEngines.count - 1 {
            // TODO: Add Custom Search Controller
        }
        
        return nil
    }

    // Don't show delete button on the left.
    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        if indexPath.section == Section.current.rawValue || indexPath.item + 1 == model.orderedEngines.count {
            return UITableViewCell.EditingStyle.none
        }

        let index = indexPath.item + 1
        let engine = model.orderedEngines[index]
        return (self.showDeletion && engine.isCustomEngine) ? .delete : .none
    }

    // Don't reserve space for the delete button on the left.
    override func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        return false
    }

    // Hide a thin vertical line that iOS renders between the accessoryView and the reordering control.
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if cell.isEditing {
            for v in cell.subviews where v.frame.width == 1.0 {
                v.backgroundColor = UIColor.clear
            }
        }
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return Design.headerHeight
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        // swiftlint:disable:next force_cast
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: Constants.sectionHeaderIdentifier) as! SettingsTableSectionHeaderFooterView
        
        let sectionTitle = section == Section.current.rawValue ?
            Strings.currentlyUsedSearchEngines : Strings.quickSearchEngines
        
        headerView.titleLabel.text = sectionTitle
        return headerView
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        if indexPath.section == Section.current.rawValue || indexPath.item + 1 == model.orderedEngines.count {
            return false
        } else {
            return true
        }
    }

    override func tableView(_ tableView: UITableView, moveRowAt indexPath: IndexPath, to newIndexPath: IndexPath) {
        // The first engine (default engine) is not shown in the list, so the indices are off-by-1.
        let index = indexPath.item + 1
        let newIndex = newIndexPath.item + 1
        let engine = model.orderedEngines.remove(at: index)
        model.orderedEngines.insert(engine, at: newIndex)
        tableView.reloadData()
    }

    // Snap to first or last row of the list of engines.
    override func tableView(_ tableView: UITableView, targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath, toProposedIndexPath proposedDestinationIndexPath: IndexPath) -> IndexPath {
        // You can't drag or drop on the default engine.
        if sourceIndexPath.section == Section.current.rawValue ||
            proposedDestinationIndexPath.section == Section.current.rawValue {
            return sourceIndexPath
        }

        //Can't drag/drop over "Add Custom Engine button"
        if sourceIndexPath.item + 1 == model.orderedEngines.count || proposedDestinationIndexPath.item + 1 == model.orderedEngines.count {
            return sourceIndexPath
        }

        if sourceIndexPath.section != proposedDestinationIndexPath.section {
            var row = 0
            if sourceIndexPath.section < proposedDestinationIndexPath.section {
                row = tableView.numberOfRows(inSection: sourceIndexPath.section) - 1
            }
            return IndexPath(row: row, section: sourceIndexPath.section)
        }
        return proposedDestinationIndexPath
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let index = indexPath.item + 1
            let engine = model.orderedEngines[index]
            
            do {
                try model.deleteCustomEngine(engine)
                tableView.deleteRows(at: [indexPath], with: .right)
            } catch {
                log.error("Search Engine Error while deleting")
            }
        }
    }
}

// MARK: - Actions

extension SearchSettingsTableViewController {
    
    @objc func didToggleEngine(_ toggle: UISwitch) {
        let engine = model.orderedEngines[toggle.tag] // The tag is 1-based.
        if toggle.isOn {
            model.enableEngine(engine)
        } else {
            model.disableEngine(engine)
        }
    }

    @objc func didToggleSearchSuggestions(_ toggle: UISwitch) {
        // Setting the value in settings dismisses any opt-in.
        model.shouldShowSearchSuggestions = toggle.isOn
        model.shouldShowSearchSuggestionsOptIn = false
    }

    @objc func dismissAnimated() {
        self.dismiss(animated: true, completion: nil)
    }
}

// MARK: SearchEnginePickerDelegate

extension SearchSettingsTableViewController: SearchEnginePickerDelegate {
    
    func searchEnginePicker(_ searchEnginePicker: SearchEnginePicker?,
                            didSelectSearchEngine searchEngine: OpenSearchEngine?, forType: DefaultEngineType?) {
        if let engine = searchEngine, let type = forType {
            model.updateDefaultEngine(engine.shortName, forType: type)
            self.tableView.reloadData()
        }
        _ = navigationController?.popViewController(animated: true)
    }
}
