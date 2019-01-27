//
//  ViewController.swift
//  Flight Data
//
//  Created by ace on 12/22/18.
//  Copyright © 2018 Ace. All rights reserved.
//

import Foundation
import UIKit
import CoreLocation
import CoreMotion

class ViewController: UIViewController, UITextViewDelegate, CLLocationManagerDelegate, UITextFieldDelegate {
    
    // MARK: Labels
    @IBOutlet weak var speedLabel: UILabel!
    @IBOutlet weak var altLabel: UILabel!
    @IBOutlet weak var dAltLabel: UILabel!
    @IBOutlet weak var speedTreshLabel: UILabel!
    @IBOutlet weak var speedUnitsLabel: UILabel!
    @IBOutlet weak var dAltUnitsLabel: UILabel!
    @IBOutlet weak var altUnitsLabel: UILabel!
    @IBOutlet weak var absAltLabel: UILabel!
    @IBOutlet weak var altTitleLabel: UILabel!
    // Placeholder Views
    @IBOutlet weak var speedPlaceholder: UIView!
    var speedEllipse: UIBezierPath?
    @IBOutlet weak var altPlaceholder: UIView!
    // Positioning Constraints
    @IBOutlet weak var speedUnitsPos: NSLayoutConstraint!
    @IBOutlet weak var altUnitsPos: NSLayoutConstraint!
    @IBOutlet weak var dAltUnitsPos: NSLayoutConstraint!
    @IBOutlet weak var altPos: NSLayoutConstraint!
    @IBOutlet weak var dAltPos: NSLayoutConstraint!
    // Mute Button
    @IBOutlet weak var muteBtn: UIImageView!
    @IBOutlet weak var muteBtnSize: NSLayoutConstraint!
    // Alt Buttons
    @IBOutlet weak var setCurrentAltBtn: UIButton!
    
    var bgColor: UIColor?
    
    var speed = 0.0
    var prevSpeed = 0.0
    var prevSpeedTime = Date()
    var dSpeed = 0.0
    var relAlt = 0.0
    var altOffset = 0.0
    var absAlt = 0.0
    var groundAlt = 0.0
    var alts: [Double] = []
    var times: [TimeInterval] = []
    var dAlt = 0.0
    var ddAlt = 0.0
    var prevDdAlt = 0.0
    
    // MARK: Tresholds
    var speedTresh = 0.0
    var altTresh = 0.0
    let changeIntervalTresh = 30.0
    
    // MARK: Audio
    let audio = Audio()
    let freqDiffFactor = 1.0
    lazy var intervalFactor = audio.regInterval / changeIntervalTresh

    let locationManager = CLLocationManager()
    let altimeter = CMAltimeter()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        bgColor = view.backgroundColor
        
        speedPlaceholder.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(self.setSpeedTresh(_:))))
        
        muteBtn.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.muteToggle(_:))))
        
        setCurrentAltBtn.addTarget(self, action: #selector(self.setCurrentAlt(_:)), for: .touchUpInside)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        speedEllipse = UIBezierPath(ovalIn: speedPlaceholder.frame)
        
        adjustFonts()
        
        if CLLocationManager.locationServicesEnabled() {
            switch CLLocationManager.authorizationStatus() {
            case .notDetermined:
                locationManager.requestWhenInUseAuthorization()
            case .restricted, .denied:
                alert("Location Services Required", "Please enable location services for this app in Settings.")
            case .authorizedAlways, .authorizedWhenInUse:
                print("Access Allowed")
            }
            
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            locationManager.distanceFilter = kCLDistanceFilterNone
            locationManager.delegate = self
            locationManager.startUpdatingLocation()
        } else {
            alert("Location Serivces Not Enabled", "Plse enable location services.")
            return
        }
        
        if !CMAltimeter.isRelativeAltitudeAvailable() {
            alert("Relative Altitude Not Available", "This device does not have an altimeter.")
            return
        }
        
        altimeter.startRelativeAltitudeUpdates(to: OperationQueue.main, withHandler: CMAltitudeHandler)
        
        mute()
        audio.start()
    }
    
    @objc func setSpeedTresh(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state != .began || !speedEllipse!.contains(gesture.location(in: view)) { return }
        
        let alert = UIAlertController(title: "Set Minimum Speed", message: "Alert below minimum speed", preferredStyle: .alert)
        
        alert.addTextField { (textField: UITextField!) in
            textField.placeholder = "Minimum Speed"
            textField.keyboardType = .numberPad
            textField.delegate = self
        }
        let prevMuted = audio.isMuted()
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { (_) in
            if !prevMuted {
                self.unmute()
            }
        }))
        alert.addAction(UIAlertAction(title: "Set", style: .default, handler: { (_) in
            let textField = alert.textFields![0] as UITextField
            if textField.text != "" {
                let tresh = Double(textField.text!)!
                self.confirm("Confirm Minimum Speed", String(format: "Are you sure you want to set the minimum speed to %.0f knots?", tresh), { (_) in
                    self.speedTresh = tresh >= 0 ? tresh : self.speedTresh
                    if self.speedTresh >= 0 {
                        self.speedTreshLabel.text = String(format: "Warn @ %.0f", self.speedTresh)
                    }
                    print("Updating Speed Treshold:", self.speedTresh)
                    self.updateAudioFreq()
                    if !prevMuted {
                        self.unmute()
                    }
                })
                
            }
            
        }))
        
        mute()
        self.present(alert, animated: true, completion: nil)
    }
    
    @objc func setCurrentAlt(_ sender: UIButton!) {
        let currentAlt: Double
        if speed < 20 {
            currentAlt = 0.0
        } else if speed > 40 {
            currentAlt = 1000.0
        } else {
            setCurrentAltBtn.isEnabled = false
            return
        }
        
        altOffset = currentAlt - relAlt
        print("Updating Altitude Offset:", altOffset)
        groundAlt = absAlt - currentAlt
        
        self.updateAltLabels(nil, nil)
        self.updateAudioInterval()
    }
    
    @objc func muteToggle(_ gesture: UITapGestureRecognizer) {
        if gesture.state != .ended { return }
        
        if audio.isMuted() {
            unmute()
        } else {
            mute()
        }
    }
    
    func unmute() {
        audio.unmute()
        muteBtn.image = UIImage(named: "unmuted")
        self.updateAudioFreq()
        self.updateAudioInterval()
    }
    
    func mute() {
        audio.mute()
        muteBtn.image = UIImage(named: "muted")
    }
    
    func updateAudioFreq() {
        if speed >= 0 && speed < speedTresh {
            let adjustedAlertFrequency = audio.alertFrequency + Float(freqDiffFactor * (speedTresh - speed))
            if !audio.hell {
                audio.frequency = adjustedAlertFrequency
                print("Updaing Frequency: Alert", audio.frequency)
            }
            if speed < speedTresh - 10 && !(speed < speedTresh - 25 && dSpeed > 3 && dAlt < -70 && abs(ddAlt - prevDdAlt) < 15) {
                audio.hellMinFrequency = adjustedAlertFrequency
                audio.hell = true
                speedLabel.layer.removeAllAnimations()
                speedLabel.alpha = 1
                
                UIView.animate(withDuration: 0.3, delay: 0, options: [.repeat, .allowUserInteraction], animations: {
                    self.view.backgroundColor = self.view.backgroundColor == self.bgColor ? .red : self.bgColor
                })
            } else {
                audio.hell = false
                view.layer.removeAllAnimations()
                view.backgroundColor = bgColor
                
                UIView.animate(withDuration: 1.0 / 3, delay: 0, options: [.repeat, .allowUserInteraction], animations: {
                    self.speedLabel.alpha = self.speedLabel.alpha == 1.0 ? 0.1 : 1
                })
            }
        } else {
            audio.hell = false
            audio.frequency = audio.regFrequency
            print("Updating Frequency: Regular", audio.frequency)
            
            speedLabel.layer.removeAllAnimations()
            speedLabel.alpha = 1
            view.layer.removeAllAnimations()
            view.backgroundColor = bgColor
        }
    }
    
    func updateAudioInterval() {
        let d = relAlt + altOffset - altTresh
        if d <= changeIntervalTresh {
            audio.interval = intervalFactor * d
            if d <= 3 {
                audio.playContinuous = true
            } else {
                audio.playContinuous = false
            }
        } else {
            audio.playContinuous = false
            audio.interval = audio.regInterval
        }
        print("Updating Audio Interval:", audio.interval)
    }
    
    func updateAltLabels(_ newRelAlt: Double?, _ timestamp: TimeInterval?) {
        if newRelAlt != nil {
            let curTime = timestamp!
            let prevTime = times.last ?? -1.0
            let prevDAlt = dAlt
            relAlt = newRelAlt!
            alts.append(relAlt)
            times.append(curTime)
            if times.last! - times.first! >= 3 {
                var instants: [Double] = []
                for i in 1..<times.endIndex {
                    let begin = round((times[i - 1] - times.first!) * 10) / 10.0
                    let end = round((times[i] - times.first!) * 10) / 10.0
                    var t = Double(instants.count)
                    while begin..<end  ~= t {
                        instants.append((alts[i] - alts[i - 1]) / (times[i] - times[i - 1]))
                        t = Double(instants.count)
                    }
                }
                dAlt = (instants[0] + instants[1]*0.5 + instants[2]*0.33) / (1 + 0.5 + 0.33) * 60
                if prevTime >= 0 {
                    prevDdAlt = ddAlt
                    ddAlt = (dAlt - prevDAlt) / (curTime - prevTime)
                    print("Updating ddAlt:", ddAlt)
                }
                print("Updating dAlt:", dAlt)
                alts.removeFirst()
                times.removeFirst()
            }
        }
        
        var alt = (relAlt + altOffset).rounded()
        if alt.sign == .minus && alt == 0 {
            alt = 0
        }
        let sign = alt.sign == .plus ? "+" : ""
        let altColor: UIColor = alt > altTresh ? .red : .green
        
        var d = (50 * (dAlt / 50).rounded())
        if d.sign == .minus && d == 0 {
            d = 0
        }
        let dColor: UIColor = d >= 0 ? .black : .blue
        
        altLabel.text = String(format: "\(sign)%.0f", alt)
        altLabel.textColor = altColor
        
        dAltLabel.text = String(format: "%.0f", d)
        dAltLabel.textColor = dColor
        
        absAltLabel.text = String(format: "Current Est MSL @ %.0f", groundAlt + alt)
    }
    
    func CMAltitudeHandler(data: CMAltitudeData?, error: Error?)  {
        if error != nil {
            print("Altitude Error", error!.localizedDescription)
            return
        }
        
        updateAltLabels(Double(exactly: data!.relativeAltitude)! * 3.28084, data!.timestamp)
        updateAudioInterval()
        
        print("Updating Relative Altitude:", relAlt)
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let speedRaw = manager.location?.speed ?? -1.0
        if speed >= 0 {
            prevSpeed = speed
            speed = speedRaw * 1.94384
            dSpeed = (speed - prevSpeed) / manager.location!.timestamp.timeIntervalSince(prevSpeedTime)
            prevSpeedTime = manager.location!.timestamp
            print("Updating Speed:", speed)
        }
        
        if speed < 20 {
            setCurrentAltBtn.setTitle("Set AGL to 0", for: .normal)
            setCurrentAltBtn.isEnabled = true
        } else if speed > 40 {
            setCurrentAltBtn.setTitle("Set AGL to 1000", for: .normal)
            setCurrentAltBtn.isEnabled = true
        } else {
            setCurrentAltBtn.isEnabled = false
        }
        
        if speed.sign == .minus {
            speedLabel.text = "no GPS"
        } else {
            speedLabel.text = String(format: "%.0f", speed.rounded())
            speedLabel.textColor = audio.hell ? .black : speed < speedTresh ? .red : .green
        }
        updateAudioFreq()
        
        guard let altRaw = manager.location?.altitude else { return }
        absAlt = altRaw * 3.28084
        print("Updating Absolute Altitude:", absAlt)
    }
    
    func adjustFonts() {
        speedLabel.fitTextToHeight(speedPlaceholder.frame.height * 0.8)
        speedUnitsPos.constant = speedLabel.font.descender + 8
        speedUnitsLabel.fitTextToHeight(speedPlaceholder.frame.height * 0.1)
        speedTreshLabel.fitTextToHeight(speedPlaceholder.frame.height * 0.1)
        
        altTitleLabel.fitTextToHeight(altPlaceholder.frame.height * 0.1)
        altLabel.fitTextToHeight(altPlaceholder.frame.height * 0.7)
        altPos.constant = -(altLabel.font.ascender - altLabel.font.capHeight) + 8
        altUnitsPos.constant = altLabel.font.descender + 8
        altUnitsLabel.fitTextToHeight(altPlaceholder.frame.height * 0.1)
        absAltLabel.fitTextToHeight(altPlaceholder.frame.height * 0.1)
        
        dAltLabel.fitTextToHeight(altPlaceholder.frame.height * 0.7)
        dAltUnitsPos.constant = dAltLabel.font.descender + 8
        dAltUnitsLabel.fitTextToHeight(altPlaceholder.frame.height * 0.1)
        dAltPos.constant = -(dAltLabel.font.ascender - dAltLabel.font.capHeight) + 8
        
        muteBtnSize.constant = self.view.frame.height * 0.1
        
        setCurrentAltBtn.titleLabel!.fitTextToHeight(altPlaceholder.frame.height * 0.1)
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let allowedCharacters = CharacterSet.decimalDigits
        let characterSet = CharacterSet(charactersIn: string)
        return allowedCharacters.isSuperset(of: characterSet)
    }
    
    
    func alert(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: UIAlertController.Style.alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        self.present(alert, animated: true, completion: nil)
    }
    
    func confirm(_ title: String, _ message: String, _ handler: @escaping (UIAlertAction) -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Confirm", style: .default, handler: handler))
        
        self.present(alert, animated: true, completion: nil)
    }
}



extension UIFont {
    
    /**
     Will return the best font conforming to the descriptor which will fit in the provided bounds.
     */
    static func bestFittingFontSize(for text: String, in bounds: CGRect, fontDescriptor: UIFontDescriptor, additionalAttributes: [NSAttributedString.Key: Any]? = nil, height: CGFloat) -> CGFloat {
        var attributes = additionalAttributes ?? [:]
        
        let infiniteBounds = CGSize(width: CGFloat.infinity, height: CGFloat.infinity)
        var bestFontSize: CGFloat = height
        
        for fontSize in stride(from: bestFontSize, through: 0, by: -1) {
            let newFont = UIFont(descriptor: fontDescriptor, size: fontSize)
            attributes[.font] = newFont
            
            let currentFrame = text.boundingRect(with: infiniteBounds, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
            
            if currentFrame.height <= height {
                bestFontSize = fontSize
                break
            }
        }
        return bestFontSize
    }
    
    static func bestFittingFont(for text: String, in bounds: CGRect, fontDescriptor: UIFontDescriptor, additionalAttributes: [NSAttributedString.Key: Any]? = nil, height: CGFloat) -> UIFont {
        let bestSize = bestFittingFontSize(for: text, in: bounds, fontDescriptor: fontDescriptor, additionalAttributes: additionalAttributes, height: height)
        return UIFont(descriptor: fontDescriptor, size: bestSize)
    }
}

extension UILabel {
    func fitTextToHeight(_ height: CGFloat) {
        guard let text = text, let currentFont = font else { return }
        
        let bestFittingFont = UIFont.bestFittingFont(for: text, in: bounds, fontDescriptor: currentFont.fontDescriptor, additionalAttributes: basicStringAttributes, height: height)
        font = bestFittingFont
    }
    
    private var basicStringAttributes: [NSAttributedString.Key: Any] {
        var attribs = [NSAttributedString.Key: Any]()
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = self.textAlignment
        paragraphStyle.lineBreakMode = self.lineBreakMode
        attribs[.paragraphStyle] = paragraphStyle
        
        return attribs
    }
}
