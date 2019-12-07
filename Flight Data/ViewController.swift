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
import AVFoundation


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
    @IBOutlet weak var timeLabel: UILabel!
    // MARK: Placeholder Views
    @IBOutlet weak var speedPlaceholder: UIView!
    @IBOutlet weak var altPlaceholder: UIView!
    // MARK: Positioning Constraints
    @IBOutlet weak var altUnitsPos: NSLayoutConstraint!
    @IBOutlet weak var dAltUnitsPos: NSLayoutConstraint!
    @IBOutlet weak var altPos: NSLayoutConstraint!
    @IBOutlet weak var dAltPos: NSLayoutConstraint!
    // MARK: Mute Button
    @IBOutlet weak var muteBtn: UIImageView!
    @IBOutlet weak var muteBtnSize: NSLayoutConstraint!
    // MARK: Alt Buttons
    @IBOutlet weak var setCurrentAltBtn: UIButton!
    // MARK: Alert Buttons
    @IBOutlet weak var setAlertsBtn: UIButton!
    // MARK: Camera
    @IBOutlet weak var cameraView: PreviewView!
    
    var bgColor: UIColor?
    var inactivityTimer: Timer?
    
    var speed = 0.0
    var relAlt = 0.0
    var altOffset = 0.0
    var absAlt = 0.0
    var groundAlt = 0.0
    var alts: [Double] = []
    var times: [TimeInterval] = []
    var dAlt = 0.0
    
    var speeds: [Double] = []
    var speedTimes: [Date] = []
    var aglStart: Date?
    var agls: [Double] = []
    var aglTimes: [Date] = []
    
    // MARK: Tresholds
    public var alertSpeed = -1.0
    public var stallSpeed = -1.0
    public var safetyMargin = -1.0
    public var landingHeadwind = -1.0
    
    // MARK: Audio
    let audio = Audio()
    
    var setAGL0Timer: Timer?
    var onGround = true

    let locationManager = CLLocationManager()
    let altimeter = CMAltimeter()
    let motionManager = CMMotionManager.init()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        UIApplication.shared.isIdleTimerDisabled = true
        
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
        
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            self.setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.setupCamera()
                } else {
                    self.alert("Camera Required", "Please enable the camera for this app in Settings.")
                }
            }
        case .denied:
            alert("Camera Required", "Please enable the camera for this app in Settings.")
            return
        case .restricted:
            alert("Camera Required", "A camera is required for this app to work")
            return
        @unknown default:
            fatalError()
        }
        
        altimeter.startRelativeAltitudeUpdates(to: OperationQueue.main, withHandler: CMAltitudeHandler)
        
        mute()
        audio.start()
    }
    
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
    
    func getCamera() -> AVCaptureDevice {
        if let device = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
            return device
        } else if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            return device
        } else {
            fatalError("Missing expected back camera device.")
        }
    }
    
    func setupCamera() {
        let session = AVCaptureSession()
        session.beginConfiguration()
        guard
            let videoDeviceInput = try? AVCaptureDeviceInput(device: getCamera()),
            session.canAddInput(videoDeviceInput)
            else { return }
        session.addInput(videoDeviceInput)
        session.sessionPreset = .photo
        let photoOutput = AVCapturePhotoOutput()
        guard session.canAddOutput(photoOutput) else { return }
        session.addOutput(photoOutput)
        session.commitConfiguration()
        
        cameraView.videoPreviewLayer.session = session
        orientCameraView()

        session.startRunning()
    }
    
    func orientCameraView() {
        var orientation: AVCaptureVideoOrientation {
            switch UIApplication.shared.statusBarOrientation {
            case .landscapeRight:       return .landscapeRight
            case .landscapeLeft:        return .landscapeLeft
            case .portrait:             return .portrait
            case .portraitUpsideDown:   return .portraitUpsideDown
            default:                    return .landscapeLeft
            }
        }
        cameraView.videoPreviewLayer.connection?.videoOrientation = orientation
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        coordinator.animate(alongsideTransition: { (context) -> Void in
            self.orientCameraView()
        })
        super.viewWillTransition(to: size, with: coordinator)
    }
    
    func getPrevSecond(vals: inout [Double], times: inout [Date]) -> Double? {
        let checkDate = Date().addingTimeInterval(-1)
        if times.count < 1 {
            return nil
        }
        
        while times.count >= 2 && times[1] <= checkDate {
            times.remove(at: 0)
            vals.remove(at: 0)
        }
        if times.count >= 2 {
            times.remove(at: 0)
            vals.remove(at: 0)
            return vals[0]
        }
        if times[0] <= checkDate {
            return vals[0]
        }
        return nil
    }
    func checkOnGround() {
        if speed < stallSpeed - landingHeadwind - 10 && relAlt + altOffset < 100 {
            if !onGround {
                enableInactivityTimer()
            }
            onGround = true
            onGroundLabel.isHidden = false
        } else {
            if onGround {
                disableInactivityTimer()
            }
            onGround = false
            onGroundLabel.isHidden = true
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd HH:mm:ss"
        timeLabel.text = dateFormatter.string(from: Date())
        
        NSLog("%f %f %f", speed, relAlt + altOffset, dAlt)
    }
    
    func enableInactivityTimer() {
        NSLog("Enabling Inactivity Timer")
        inactivityTimer?.invalidate()
        inactivityTimer = Timer.scheduledTimer(timeInterval: 30 * 60, target: self, selector: #selector(self.enableIdleTimer), userInfo: nil, repeats: false)
    }
    
    func disableInactivityTimer() {
        NSLog("Disabling Inactivity Timer")
        inactivityTimer?.invalidate()
        UIApplication.shared.isIdleTimerDisabled = true
    }
    
    @objc func enableIdleTimer() {
        NSLog("Enabling Idle Timer")
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
            if #available(iOS 13.0, *) {
                muteBtn.tintColor = .label
            } else {
                muteBtn.tintColor = .black
            }
            
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
                muteBtn.tintColor = UIColor(red: 0.55, green: 0, blue: 0, alpha: 1)
                
                audio.hell = true
                audio.solidEnabled = false
                audio.intervalEnabled = false
                
                speedLabel.layer.removeAllAnimations()
                speedLabel.alpha = 1
                
                UIView.animate(withDuration: 1.0 / 3, delay: 0, options: [.repeat, .allowUserInteraction], animations: {
                    self.view.backgroundColor = self.view.backgroundColor == self.bgColor ? .red : self.bgColor
                })
            } else if speed < solidSpeed {
                if #available(iOS 13.0, *) {
                    muteBtn.tintColor = .label
                } else {
                    muteBtn.tintColor = .black
                }
                
                audio.hell = false
                audio.solidEnabled = true
                audio.intervalEnabled = false
                
                view.layer.removeAllAnimations()
                view.backgroundColor = bgColor
                UIView.animate(withDuration: 1.0 / 3, delay: 0, options: [.repeat, .allowUserInteraction], animations: {
                    self.speedLabel.alpha = self.speedLabel.alpha == 1.0 ? 0.1 : 1
                })
            } else {
                if #available(iOS 13.0, *) {
                    muteBtn.tintColor = .label
                } else {
                    muteBtn.tintColor = .black
                }
                
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
        // let altColor: UIColor = alt > altTresh ? .red : .green
        
        var d = (50 * (dAlt / 50).rounded())
        if d.sign == .minus && d == 0 {
            d = 0
        }
        let dSign = d >= 0 ? "+" : ""
        let dColor: UIColor = d >= 0 ? .blue : .red
        
        if timestamp != nil {
            agls.append(relAlt + altOffset)
            aglTimes.append(aglStart!.addingTimeInterval(timestamp!))
        }
        
        altLabel.text = String(format: "%.0f", alt)
        // altLabel.textColor = altColor
        
        dAltLabel.text = String(format: "\(dSign)%.0f", d)
        dAltLabel.textColor = dColor
        
        absAltLabel.text = String(format: "Current Est MSL @ %.0f", groundAlt + alt)
        
        checkOnGround()
    }
    
    func CMAltitudeHandler(data: CMAltitudeData?, error: Error?)  {
        if error != nil {
            print("Altitude Error", error!.localizedDescription)
            return
        }
        if aglStart == nil {
            aglStart = Date().addingTimeInterval(-data!.timestamp)
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
                speedLabel.fitTextToHeight(speedPlaceholder.frame.height * 0.2)
            }
            speedLabel.text = "no GPS"
            speedLabel.textColor = .red
        } else {
            speed = speedRaw * 1.94384
            print("Updating Speed:", speed)
        
            speeds.append(speed)
            speedTimes.append(manager.location!.timestamp)
            
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
                speedLabel.fitTextToHeight(speedPlaceholder.frame.height * 1.1)
            }
            speedLabel.text = String(format: "%.0f", speed.rounded())
            speedLabel.textColor = audio.hell ? .black : speed < alertSpeed ? .red : .green
        }
        checkOnGround()
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
        
        speedLabel.fitTextToHeight(speedPlaceholder.frame.height * 0.2)
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


class PreviewView: UIView {
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    /// Convenience wrapper to get layer as its statically known type.
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
}
