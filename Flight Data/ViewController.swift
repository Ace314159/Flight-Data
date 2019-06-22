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
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var onGroundLabel: UILabel!
    // Placeholder Views
    @IBOutlet weak var speedPlaceholder: UIView!
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
    // Alert Buttons
    @IBOutlet weak var setAlertsBtn: UIButton!
    
    var bgColor: UIColor?
    var inactivityTimer: Timer?
    
    var speed = 0.0
    // var prevSpeed = 0.0
    // var prevSpeedTime = Date()
    // var dSpeed = 0.0
    var relAlt = 0.0
    var altOffset = 0.0
    var absAlt = 0.0
    var groundAlt = 0.0
    var alts: [Double] = []
    var times: [TimeInterval] = []
    var dAlt = 0.0
    /*var ddAlt = 0.0
    var prevDdAlt = 0.0*/
    
    // MARK: Tresholds
    //var speedTresh = -1.0
    public var alertSpeed = -1.0
    public var stallSpeed = -1.0
    public var safetyMargin = -1.0
    public var landingHeadwind = -1.0
    // var altTresh = 0.0
    // let changeIntervalTresh = 30.0
    
    // MARK: Audio
    let audio = Audio()
    /*let minAudioSpeed = 20.0
    let maxAudioSpeed = 100.0
    var higherPitch = true
    lazy var intervalFactor = audio.regInterval / changeIntervalTresh
    
    var alternatingPitchTimer: Timer?
    var alternatingPitchOriginal = true
    var originalAlternatingPitch: Float = 0.0
    var otherAlternatingPitch: Float = 0.0*/
    
    var setAGL0Timer: Timer?
    var onGround = true
    /*var prevOnGroundTime = Date()
    
    var prevLanding = Date()
    var prevTakeoff = Date()*/

    let locationManager = CLLocationManager()
    let altimeter = CMAltimeter()
    let motionManager = CMMotionManager.init()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let navigationController = UINavigationController(rootViewController: self)
        (UIApplication.shared.delegate as! AppDelegate).window!.rootViewController = navigationController
        
        enableInactivityTimer()
        
        setAGL0Timer = Timer.scheduledTimer(timeInterval: 60, target: self, selector: #selector(self.setAGL0), userInfo: nil, repeats: false)
        
        bgColor = view.backgroundColor
        
        muteBtn.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.muteToggle(_:))))
        
        setAlertsBtn.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.setAlerts(_:))))
        
        setCurrentAltBtn.addTarget(self, action: #selector(self.setCurrentAlt(_:)), for: .touchUpInside)
        
        let alerts = Alerts()
        alerts.preventBack = true
        navigationController.pushViewController(alerts, animated: true)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        navigationController?.setNavigationBarHidden(true, animated: false)
        
        speedTreshLabel.text = String(format: "Warn @ %.0f", alertSpeed)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        adjustFonts()
        
        if CLLocationManager.locationServicesEnabled() {
            switch CLLocationManager.authorizationStatus() {
            case .notDetermined:
                locationManager.requestWhenInUseAuthorization()
            case .restricted, .denied:
                alert("Location Services Required", "Please enable location services for this app in Settings.")
            case .authorizedAlways, .authorizedWhenInUse:
                print("Access Allowed")
            @unknown default:
                fatalError()
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
        
        // motionManager.gyroUpdateInterval = 0.1
        motionManager.accelerometerUpdateInterval = 0.1
        // motionManager.startGyroUpdates(to: OperationQueue.main, withHandler: CMGyroHandler)
        motionManager.startAccelerometerUpdates(to: OperationQueue.main, withHandler: CMAccelerometerHandler)
        
        mute()
        audio.start()
        
        // setSpeedTresh()
    }
    
    func CMAccelerometerHandler(data: CMAccelerometerData?, error: Error?) {
        if error != nil {
            return
        }
        
        if data!.acceleration.y < -0.5 {
            if dAlt > 0 {
                onGround = false
                onGroundLabel.isHidden = true
                disableInactivityTimer()
            } else if dAlt < 0 {
                onGround = true
                onGroundLabel.isHidden = false
                enableInactivityTimer()
            }
        }
        
        /*let x = String(format: "%.5f", data!.acceleration.x)
        let y = String(format: "%.5f", data!.acceleration.y)
        let z = String(format: "%.5f", data!.acceleration.z)
        
        accelLabel.text = [x, y, z].joined(separator: " ")*/
    }
    
    /*func CMGyroHandler(data: CMGyroData?, error: Error?) {
        if error != nil {
            return
        }
        
        let x = String(format: "%.5f", data!.rotationRate.x)
        let y = String(format: "%.5f", data!.rotationRate.y)
        let z = String(format: "%.5f", data!.rotationRate.z)

        gyroLabel.text = [x, y, z].joined(separator: " ")
    }*/
    
    @objc func setAlerts(_ sender: UIButton?) {
        audio.mute()
        let newAlerts = Alerts()
        navigationController?.pushViewController(newAlerts, animated: true)
    }
    
    @objc func setCurrentAlt(_ sender: UIButton?) {
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
        // self.updateAudioInterval()
    }
    
    @objc func muteToggle(_ gesture: UITapGestureRecognizer) {
        if gesture.state != .ended { return }
        
        if audio.isMuted() {
            unmute()
        } else {
            mute()
        }
    }
    
    func enableInactivityTimer() {
        inactivityTimer = Timer.scheduledTimer(timeInterval: 18 * 60, target: self, selector: #selector(self.enableIdleTimer), userInfo: nil, repeats: false)
    }
    
    func disableInactivityTimer() {
        inactivityTimer?.invalidate()
        UIApplication.shared.isIdleTimerDisabled = true
    }
    
    @objc func enableIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = false
    }
    
    @objc func setAGL0() {
        if speed < 2 && dAlt < 50 {
            setCurrentAlt(nil)
        }
    }
    
    func unmute() {
        audio.unmute()
        muteBtn.image = UIImage(named: "unmuted")
        self.updateAudio()
        // self.updateAudioInterval()
    }
    
    func mute() {
        audio.mute()
        muteBtn.image = UIImage(named: "muted")
    }
    
    func updateAudio() {
        if speed > alertSpeed || onGround {
            audio.hell = false
            audio.solidEnabled = false
            audio.intervalEnabled = false
            
            speedLabel.layer.removeAllAnimations()
            speedLabel.alpha = 1
            view.layer.removeAllAnimations()
            view.backgroundColor = bgColor
        } else {
            let solidSpeed = alertSpeed - safetyMargin / 2
            if speed < stallSpeed - landingHeadwind + 3 {
                audio.hell = true
                audio.solidEnabled = false
                audio.intervalEnabled = false
                
                speedLabel.layer.removeAllAnimations()
                speedLabel.alpha = 1
                
                UIView.animate(withDuration: 1.0 / 3, delay: 0, options: [.repeat, .allowUserInteraction], animations: {
                    self.view.backgroundColor = self.view.backgroundColor == self.bgColor ? .red : self.bgColor
                })
            } else if speed < solidSpeed {
                audio.hell = false
                audio.solidEnabled = true
                audio.intervalEnabled = false
                
                view.layer.removeAllAnimations()
                view.backgroundColor = bgColor
                UIView.animate(withDuration: 1.0 / 3, delay: 0, options: [.repeat, .allowUserInteraction], animations: {
                    self.speedLabel.alpha = self.speedLabel.alpha == 1.0 ? 0.1 : 1
                })
            } else {
                audio.hell = false
                audio.solidEnabled = false
                audio.intervalEnabled = true
                
                speedLabel.layer.removeAllAnimations()
                speedLabel.alpha = 1
                view.layer.removeAllAnimations()
                view.backgroundColor = bgColor
            }
            
        }
    }
    
    func updateAltLabels(_ newRelAlt: Double?, _ timestamp: TimeInterval?) {
        if newRelAlt != nil {
            let curTime = timestamp!
            // let prevTime = times.last ?? -1.0
            // let prevDAlt = dAlt
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
                /*if prevTime >= 0 {
                    prevDdAlt = ddAlt
                    ddAlt = (dAlt - prevDAlt) / (curTime - prevTime)
                    print("Updating ddAlt:", ddAlt)
                }*/
                print("Updating dAlt:", dAlt)
                alts.removeFirst()
                times.removeFirst()
            }
        }
        if dAlt >= 50 {
            setAGL0Timer?.invalidate()
        }
        
        var alt = (relAlt + altOffset).rounded()
        if alt.sign == .minus && alt == 0 {
            alt = 0
        }
        let sign = alt.sign == .plus ? "+" : ""
        // let altColor: UIColor = alt > altTresh ? .red : .green
        
        var d = (50 * (dAlt / 50).rounded())
        if d.sign == .minus && d == 0 {
            d = 0
        }
        let dColor: UIColor = d >= 0 ? .black : .blue
        
        altLabel.text = String(format: "\(sign)%.0f", alt)
        // altLabel.textColor = altColor
        
        dAltLabel.text = String(format: "%.0f", d)
        dAltLabel.textColor = dColor
        
        
        absAltLabel.text = String(format: "Current Est MSL @ %.0f", groundAlt + alt)
    }
    
    func CMAltitudeHandler(data: CMAltitudeData?, error: Error?)  {
        if error != nil {
            print("Altitude Error", error!.localizedDescription)
            return
        }
        // rawAltLabel.text = data!.relativeAltitude.stringValue
        
        updateAltLabels(data!.relativeAltitude.doubleValue * 3.28084, data!.timestamp)
        // updateAudioInterval()
        
        print("Updating Relative Altitude:", relAlt)
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let speedRaw = manager.location?.speed ?? -1.0
        
        if speedRaw < 0 {
            speed = 0
            /*prevSpeed = 0
            dSpeed = 0
            prevSpeedTime = manager.location!.timestamp*/
            print("Updating Speed - Invalid:", speedRaw)

            setCurrentAltBtn.setTitle("Set AGL", for: .normal)
            setCurrentAltBtn.isEnabled = false
            
            if speedLabel.text != "no GPS" {
                speedLabel.fitTextToHeight(speedPlaceholder.frame.height * 0.5)
            }
            speedLabel.text = "no GPS"
            speedLabel.textColor = .red
        } else {
            speed = speedRaw * 1.94384
            print("Updating Speed:", speed)
            /*prevSpeed = speed
            dSpeed = (speed - prevSpeed) / manager.location!.timestamp.timeIntervalSince(prevSpeedTime)
            prevSpeedTime = manager.location!.timestamp
            
            if speed < 30 && dAlt < 50 {
                prevOnGroundTime = Date()
            }
            if prevOnGroundTime.timeIntervalSinceNow < -5 {
                onGround = false
                onGroundLabel.isHidden = true
            } else {
                onGround = true
                onGroundLabel.isHidden = false
            }*/
            
            if speed >= 2 {
                setAGL0Timer?.invalidate()
            }
            
            if speed < 20 {
                setCurrentAltBtn.setTitle("Set AGL to 0", for: .normal)
                setCurrentAltBtn.isEnabled = true
            } else if speed > 40 {
                setCurrentAltBtn.setTitle("Set AGL to 1000", for: .normal)
                setCurrentAltBtn.isEnabled = true
            } else {
                setCurrentAltBtn.setTitle("Set AGL", for: .normal)
                setCurrentAltBtn.isEnabled = false
            }
            
            if speedLabel.text == "no GPS" {
                speedLabel.fitTextToHeight(speedPlaceholder.frame.height * 0.7)
            }
            speedLabel.text = String(format: "%.0f", speed.rounded())
            speedLabel.textColor = audio.hell ? .black : speed < alertSpeed ? .red : .green
        }
        updateAudio()
        
        guard let altRaw = manager.location?.altitude else { return }
        absAlt = altRaw * 3.28084
        print("Updating Absolute Altitude:", absAlt)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location Error:", error)
        alert("Location Error", error.localizedDescription)
    }
    
    func adjustFonts() {
        titleLabel.fitTextToHeight(altPlaceholder.frame.height * 0.15)
        
        speedLabel.fitTextToHeight(speedPlaceholder.frame.height * 0.7)
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
        setAlertsBtn.titleLabel!.fitTextToHeight(speedPlaceholder.frame.height * 0.1)
    }
    
    
    func alert(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: UIAlertController.Style.alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
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
