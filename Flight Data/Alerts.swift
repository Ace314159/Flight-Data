//
//  Alerts.swift
//  Flight Data
//
//  Created by Akash Munagala on 5/23/19.
//  Copyright © 2019 Ace. All rights reserved.
//

import Foundation
import Eureka
import APNumberPad

class Alerts: FormViewController {
    public var preventBack = false
    
    var stallSpeed: Int? = UserDefaults.standard.object(forKey: "stallSpeed") as! Int?
    var safetyMargin: Int? = UserDefaults.standard.object(forKey: "safetyMargin") as! Int?
    var landingHeadwind = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Set Groundspeed Alerts"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", style: .done, target: self, action: #selector(saveAlerts))
        if preventBack {
            navigationItem.hidesBackButton = true
        }

        form +++ Section()
            <<< iPadIntRow() { row in
                row.title = "Stall Speed"
                row.tag = "stallSpeed"
                row.placeholder = "knots"
                row.value = stallSpeed
                row.add(rule: RuleRequired(msg: "Stall Speed Required!"))
                row.add(rule: RuleGreaterOrEqualThan(min: 40, msg: "Stall Speed must be greater than 40 knots!"))
                }.onChange { row in
                    self.stallSpeed = row.value
                    self.setAlertSpeed()
                    _ = self.form.rowBy(tag: "landingHeadwind")?.validate()
                }.onRowValidationChanged(manageValidationErrors)
            <<< iPadIntRow() { row in
                row.title = "Safety Margin"
                row.tag = "safetyMargin"
                row.placeholder = "knots (> 10)"
                row.value = safetyMargin
                row.add(rule: RuleRequired(msg: "Safety Margin Required!"))
                row.add(rule: RuleGreaterOrEqualThan(min: 10, msg: "Safety Margin must be greater than 10 knots!"))
                row.validationOptions = .validatesOnBlur
                }.onChange { row in
                    self.safetyMargin = row.value
                    self.setAlertSpeed()
                    _ = self.form.rowBy(tag: "landingHeadwind")?.validate()
                }.onRowValidationChanged(manageValidationErrors)
            <<< iPadIntRow() { row in
                row.title = "Landing Headwind"
                row.tag = "landingHeadwind"
                row.placeholder = "knots"
                row.add(rule: RuleRequired(msg: "Landing Headwind Required!"))
                let rule = RuleClosure<Int> { rowValue in
                    let actualStallSpeed = self.stallSpeed ?? 0
                    let actualSafetyMargin = self.safetyMargin ?? 0
                    return (rowValue ?? 0) > actualStallSpeed + actualSafetyMargin ? ValidationError(msg: "Landing Headwind too high. Alert speed cannot be negative!") : nil
                }
                row.add(rule: rule)
                row.validationOptions = .validatesOnChange
                }.onChange { row in
                    self.landingHeadwind = row.value ?? 0
                    self.setAlertSpeed()
                    if row.isValid && self.form.rowBy(tag: "stallSpeed")!.isValid && self.form.rowBy(tag: "safetyMargin")!.isValid {
                        self.navigationItem.rightBarButtonItem?.isEnabled = true
                    }
                }.onRowValidationChanged(manageValidationErrors(cell:row:))
            <<< LabelRow() { row in
                row.title = "Alert Speed"
                row.tag = "alertSpeed"
                row.value = "0 knots GS"
                }
            +++ Section()
            <<< ButtonRow() { row in
                row.title = "Read More"
                row.onCellSelection { cell, row in
                    let alert = UIAlertController(title: "Read More", message: "This app was developed by Akash Munagala and designed by Ivo Welch.\n\nThis app has no association with the AOPA.\n\nA pilot can use the iPad video record button (swipe down from top right) to record flights.", preferredStyle: UIAlertController.Style.alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    
                    self.present(alert, animated: true, completion: nil)
                }
                }
        
        navigationItem.rightBarButtonItem?.isEnabled = false
        if stallSpeed != nil {
            _ = form.rowBy(tag: "stallSpeed")?.validate()
        }
        if safetyMargin != nil {
            _ = form.rowBy(tag: "safetyMargin")?.validate()
        }
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            let textView = UITextView(frame: CGRect(x: 0, y: 400, width: UIScreen.main.bounds.width, height: 200))
            textView.text = "We have spent many hours developing this app, but we find it difficult to reach pilots. Please tell your pilot friends about our app. Thank you!"
            textView.isEditable = false
            textView.font = UIFont(name: textView.font!.fontName, size: 50)
            textView.textAlignment = NSTextAlignment.center
            textView.isScrollEnabled = false
            let fixedWidth = textView.frame.size.width
            let newSize = textView.sizeThatFits(CGSize(width: fixedWidth, height: CGFloat.greatestFiniteMagnitude))
            textView.frame.size = CGSize(width: max(newSize.width, fixedWidth), height: newSize.height)
            view.addSubview(textView)
        }
    }
    
    func manageValidationErrors(cell: iPadIntCell, row: iPadIntRow) {
        let rowIndex = row.indexPath!.row
        while row.section!.count > rowIndex + 1 && row.section?[rowIndex  + 1] is LabelRow {
            if row.section?[rowIndex + 1].tag != nil {
                break
            }
            row.section?.remove(at: rowIndex + 1)
        }
        if !row.isValid {
            for (index, validationMsg) in row.validationErrors.map({ $0.msg }).enumerated() {
                let labelRow = LabelRow() {
                    $0.title = validationMsg
                    $0.cell.height = { 30 }
                }
                let at = row.indexPath!.row + index + 1
                row.section?.insert(labelRow, at: at)
                labelRow.cell.textLabel?.textColor = .red
            }
        }
        
        navigationItem.rightBarButtonItem?.isEnabled = form.rowBy(tag: "stallSpeed")!.isValid && form.rowBy(tag: "safetyMargin")!.isValid && form.rowBy(tag: "landingHeadwind")!.isValid
    }
    
    func setAlertSpeed() {
        if(!form.validate().isEmpty) { return }
        let alertRow: LabelRow = form.rowBy(tag: "alertSpeed") as! LabelRow
        let actualStallSpeed = stallSpeed ?? 0
        let actualSafetyMargin = safetyMargin ?? 0
        
        alertRow.value = String(actualStallSpeed + actualSafetyMargin - landingHeadwind) + " knots GS"
        alertRow.reload()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        navigationController?.setNavigationBarHidden(false, animated: false)
        
        /*var firstResponder: iPadIntRow
        if stallSpeed == nil {
            firstResponder = form.rowBy(tag: "stallSpeed")!
        } else if safetyMargin == nil {
            firstResponder = form.rowBy(tag: "safetyMargin")!
        } else {
            firstResponder = form.rowBy(tag: "landingHeadwind")!
        }
        firstResponder.cell.textField.becomeFirstResponder()*/
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        let enableTime: Date? = UserDefaults.standard.object(forKey: "enableTime") as? Date
        if enableTime != nil && enableTime!.timeIntervalSinceNow > 0 {
            let alert = UIAlertController(title: "Demo Period Expired", message: "Please wait for another \(Int(ceil(enableTime!.timeIntervalSinceNow / 60))) minutes", preferredStyle: UIAlertController.Style.alert)
            self.present(alert, animated: true)
            return
        }
        
        if UIDevice.current.userInterfaceIdiom == .phone {
            let alert = UIAlertController(title: "Please Share This App", message: "We have spent many hours developing this app, but we find it difficult to reach pilots. Please tell your pilot friends about our app. Thank you!", preferredStyle: UIAlertController.Style.alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
        }
    }
    
    @objc func saveAlerts() {
        UserDefaults.standard.set(stallSpeed, forKey: "stallSpeed")
        UserDefaults.standard.set(safetyMargin, forKey: "safetyMargin")
        
        (navigationController?.viewControllers[0] as! ViewController).alertSpeed = Double(stallSpeed! + safetyMargin! - landingHeadwind)
        (navigationController?.viewControllers[0] as! ViewController).stallSpeed = Double(stallSpeed!)
        (navigationController?.viewControllers[0] as! ViewController).safetyMargin = Double(safetyMargin!)
        (navigationController?.viewControllers[0] as! ViewController).landingHeadwind = Double(landingHeadwind)
        
        navigationController?.popViewController(animated: true)
    }
}

final class iPadIntRow: FieldRow<iPadIntCell>, RowType {
    required public init(tag: String?) {
        super.init(tag: tag)
    }
}

class iPadIntCell: _FieldCell<Int>, CellType, APNumberPadDelegate {
    open override func setup() {
        super.setup()
        
        let numberPad = APNumberPad(delegate: self)
        numberPad.leftFunctionButton.setTitle("", for: .disabled)
        
        textField.inputView = numberPad
        textField.autocorrectionType = .no
        textField.inputAssistantItem.trailingBarButtonGroups.removeAll()
        textField.inputAssistantItem.leadingBarButtonGroups.removeAll()
    }
}
