//
//  ViewController.swift
//  RHAnimator
//
//  Created by Rolf Hendriks on 8/11/17.
//  Copyright © 2017 Rolf Hendriks. All rights reserved.
//

import UIKit


class ViewController: UIViewController {

    @IBOutlet weak var rootStackView: UIStackView!
    @IBOutlet weak var animationCurveButton: UIButton!
    @IBOutlet weak var animationDurationTextField: UITextField!
    @IBOutlet weak var animationDurationStepper: UIStepper!
    @IBOutlet weak var animationDurationSlider: UISlider!
    @IBOutlet weak var animationDurationLabel: UILabel!
    
    @IBOutlet weak var translationView: UIView!
    @IBOutlet weak var rotateAnimationView: UIView!
    @IBOutlet weak var scaleAnimationView: UIView!
    @IBOutlet weak var colorAnimationView: UIView!

    @IBOutlet weak var graphView: RHFunctionGraphView!
    
    // curves
    let titleKey = "title"
    let curveKey = "curve"
    let enumKey = "enum"
    enum DemoCurve{
        
        case ease;
        case easeIn;
        case easeOut;
        case linear;
        
        case strongEase;
        case strongEaseIn;
        case strongEaseOut;
        
        case exponentialEaseOut;
        
        case overshoot;
        case overshoot3;
        
        case shake;
    }
    lazy var animationCurveData : [[String:Any]] = {[
        // normal easing animations, just like UIKit has
        [self.enumKey:DemoCurve.ease, self.titleKey:"Ease", self.curveKey:RHAnimationCurves.easeInOut],
        [self.enumKey:DemoCurve.easeIn, self.titleKey:"Ease In", self.curveKey:RHAnimationCurves.easeIn],
        [self.enumKey:DemoCurve.easeOut, self.titleKey:"Ease Out", self.curveKey:RHAnimationCurves.easeOut],
        [self.enumKey:DemoCurve.linear, self.titleKey:"Linear", self.curveKey:RHAnimationCurves.linear],
        
        // parameterized easing alternatives
        [self.enumKey:DemoCurve.strongEase, self.titleKey:"Strong Ease", self.curveKey:RHAnimationCurves.ease(strength:3)],
        [self.enumKey:DemoCurve.strongEaseOut, self.titleKey:"Strong Ease Out", self.curveKey:RHAnimationCurves.decelerate(strength:3)],
        
        // exponential curves, great for easing out
        [self.enumKey:DemoCurve.exponentialEaseOut, self.titleKey:"Exponential Ease Out", self.curveKey:RHAnimationCurves.exponentialDecelerate()],
        
        // overshoot/spring animations
        [self.enumKey:DemoCurve.overshoot, self.titleKey:"Overshoot", self.curveKey:RHAnimationCurves.overshoot()],
        [self.enumKey:DemoCurve.overshoot3, self.titleKey:"Overshootx3", self.curveKey:RHAnimationCurves.overshoot(count:3)],
        
        // and just for fun: shake animation
        [self.enumKey:DemoCurve.shake, self.titleKey:"Shake", self.curveKey:self.shakeCurve(shakes:5)]
    ]}()
    var selectedCurveIndex : Int = 0
    
    //-------------------------------------------------------
    
    // MARK: PRIVATE
    
    // MARK: Properties
    private let maximumRotationDegrees : CGFloat = 60
    private let maximumScale : CGFloat = 1.5
    private let defaultHue : CGFloat = 5 / 8.0
    private let maximumHueShift : CGFloat = 0.3
    
    var animationDuration : TimeInterval = 1
    
    private var animationCurvePicker : UIPickerView? = nil
    
    private var animation : RHAnimator? = nil
    // animations keep cycling: forward, back to center, backwards, back to center, etc
    private enum AnimationPhase : Int{
        case forward
        case forwardRevert
        case backward
        case backwardRevert
    }
    private var animationPhase : AnimationPhase = .forward
    private var animationPhasePauseDuration : TimeInterval = 0.5 // time to pause/rest in between phases

    
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        self.configureColors()
        if let label = self.animationCurveButton.titleLabel{
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.5
        }
        // UI from Interface Builder and actual data may diverge. Let's treat
        //  our data as the source of truth and IB's values as placeholders:
        self.refreshAnimationCurveButton()
        self.configureFunctionGraph()
        self.refreshFunctionGraph()
        beginAnimations()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        // change layout between portrait + landscape orientations
        let wasWideFormat : Bool = self.view.bounds.size.width > self.view.bounds.size.height
        let isWideFormat : Bool = size.width > size.height
        if (isWideFormat != wasWideFormat){
            self.rootStackView.axis = isWideFormat ? .horizontal : .vertical
            if (self.animationCurvePicker != nil){
                self.dismissPicker()
            }
        }
    }
    
    
    // MARK: Animations
    func shakeCurve (shakes:Int) -> (RHAnimator.Interpolation){
        return { (x : Double) in
            // implement back + forth shaking as a sine wave
            let waveCount : Double = Double(shakes)
            let sineValue : Double = sin ( x*waveCount * 2*Double.pi )
            
            // also need to implement a damping function. How about just an exponential decay?
            //let damping : Double = RHAnimationCurves.decay()(x)
            // or how about easing from no shaking, to full shaking, back to no shaking?
            let ease : RHAnimator.Interpolation = RHAnimationCurves.easeInOut
            let damping : Double = x <= 0.5 ? ease( 2*x ) : 1 - ease( 2*(x-0.5) )
            
            return sineValue * damping
        }
    }
    var animationCurve : RHAnimator.Interpolation {
        return self.animationCurveData[self.selectedCurveIndex][self.curveKey] as! RHAnimator.Interpolation
    }
    var animationCurveDescription : String {
        return self.animationCurveData[self.selectedCurveIndex][self.titleKey] as! String
    }
    var animationCurveEnum : DemoCurve {
        return self.animationCurveData[self.selectedCurveIndex][self.enumKey] as! DemoCurve
    }
    private func beginAnimations(){
        self.animation = RHAnimator.animate ( duration:self.animationDuration, curve:self.animationCurve,
        animation:{
            progress in self.update(progress)
        },completion:{
            self.animationFinished()
        })
    }
    
    private func update (_ progress : Double ){
        
        // implement four phase animation cycle for demo purposes:
        //  1. normal animation
        //  2. back to original state
        //  3. negative animation / opposite direction
        //  4. back to original state
        //  etc
        
        // In a real world setting, the animation setup would be much simpler 
        // because this four phase cycle is an artificial construct.
        let backward : Bool = self.animationPhase.rawValue >= AnimationPhase.backward.rawValue
        let reverting : Bool = self.animationPhase == .backwardRevert || self.animationPhase == .forwardRevert
        let directionMultiplier : CGFloat = backward ? -1 : 1
        var t : Double = progress
        if (reverting)
        {
            // using 1-t to revert animations works in most cases, but it hardcodes the 
            // assumption that animations always end at their target value. Some unusual 
            // animations, like the shake animation, could break this assumption though.
            let finalValue : Double = self.animationCurve(1)
            t = finalValue - t
        }
        
        // move/translation animation
        let parent : UIView = self.translationView.superview!
        let maxCenterXOffset : CGFloat = directionMultiplier * ((parent.bounds.width - 0.5*self.translationView.bounds.width) - 0.5 * parent.bounds.width) // offset to move sliding view from center to far left or right, depending on animation phase
        let moveTransform : CGAffineTransform = CGAffineTransform(translationX:maxCenterXOffset * t, y: 0)
        self.translationView.transform = moveTransform
        
        // rotate animation
        let rotationDegrees : CGFloat = self.maximumRotationDegrees * t * directionMultiplier
        let rotationTransform : CGAffineTransform = CGAffineTransform(rotationAngle: rotationDegrees * CGFloat.pi / 180)
        self.rotateAnimationView.transform = rotationTransform
        
        // scale animation
        let maxScale : CGFloat = backward ? 1 / self.maximumScale : self.maximumScale
        let scale : CGFloat = RHAnimator.interpolate(from: 1.0, to: maxScale, at: t)
        //let scale = RHAnimator.interpolateCGFloat(from: 1.0, to: maxScale, at: t)
        let scaleTransform : CGAffineTransform = CGAffineTransform(scaleX: scale, y: scale)
        self.scaleAnimationView.transform = scaleTransform
        
        // color animation
        let hue : CGFloat = self.defaultHue + directionMultiplier * self.maximumHueShift * t
        var s:CGFloat=0, b:CGFloat=0, a:CGFloat=0
        self.colorAnimationView.backgroundColor?.getHue( nil, saturation: &s, brightness: &b, alpha: &a)
        self.colorAnimationView.backgroundColor = UIColor(hue: hue, saturation: s, brightness: b, alpha: a)
    }
    
    private func animationFinished(){
        // implement pause between phases
        DispatchQueue.main.asyncAfter(
            deadline: DispatchTime.now() + self.animationPhasePauseDuration,
            execute: {
                self.nextAnimationPhase()
            }
        )
    }
    
    private func nextAnimationPhase(){
        if let nextAnimationPhase = AnimationPhase (rawValue:self.animationPhase.rawValue + 1){
            self.animationPhase = nextAnimationPhase
        }else {
            self.animationPhase = .forward
        }

        // Create a new animator to handle potential changes in animation curve or duration.
        // As a convention for this demo, changing parameters mid-animation applies those changes
        // to the next animation phase. Changing parameters mid-animation
        // is not a practical use case and is not supported by RHAnimator.
        self.beginAnimations()
    }
    
    
    
    // MARK: Animation Curve Button + Picker
    @IBAction private func onAnimationCurveButton(){
        if (self.animationCurvePicker == nil)
        {
            self.animationCurvePicker = self.createPicker()
            self.showPicker()
            self.setFunctionGraphVisible(false)
        }
    }
    
    func createPicker() -> UIPickerView{
        let picker : UIPickerView = UIPickerView();
        picker.showsSelectionIndicator = true
        picker.delegate = self
        picker.dataSource = self
        
        // add a dividing line between picker and rest of UI.
        // This needs to work when sliding in from the bottom or from the side. 
        // A quick + easy way to do this is to position top + left dividers 1px 
        // beyond the pickers' bounds:
        let topDivider : UIView = UIView (frame: CGRect(x: 0, y: -1, width: picker.bounds.width, height: 1))
        topDivider.backgroundColor = UIColor.black
        topDivider.autoresizingMask = [.flexibleWidth, .flexibleBottomMargin]
        picker.addSubview( topDivider )
        
        let leftDivider : UIView = UIView (frame: CGRect(x:-1, y:0, width:1, height:picker.bounds.height))
        leftDivider.autoresizingMask = [.flexibleHeight, .flexibleRightMargin]
        leftDivider.backgroundColor = UIColor.black
        picker.addSubview( leftDivider )
        
        picker.clipsToBounds = false
        return picker
    }
    
    var showHidePickerDuration : TimeInterval { return self.animationDuration/2 }
    
    var pickerAnimationCurve : RHAnimator.Interpolation{
        // Use our own animation util + custom curve for showing/hiding the picker
        let customCurve : RHAnimator.Interpolation = self.animationCurve
        return customCurve(1) == 1 ? customCurve : RHAnimationCurves.easeInOut
    }
    
    
    func showPicker(){
        if let picker = self.animationCurvePicker{
            picker.selectRow(self.selectedCurveIndex, inComponent: 0, animated: false)
            
            // final position: bottom half or right half of screen, depending on 
            //  orientation
            let isWide : Bool = self.view.bounds.width > self.view.bounds.height
            var toFrame : CGRect = self.view.bounds
            toFrame.origin.y = self.rootStackView.frame.origin.y
            toFrame.size.height -= toFrame.origin.y
            if (isWide){
                toFrame.origin.x = toFrame.midX
                toFrame.size.width /= 2
            }
            else{
                toFrame.origin.y = toFrame.midY
                toFrame.size.height /= 2
            }
            
            // original position: off the screen
            var fromPosition : CGPoint = toFrame.origin
            if (isWide){
                fromPosition.x += toFrame.width
            }
            else{
                fromPosition.y += toFrame.height
            }
            
            picker.frame = CGRect(origin: fromPosition, size: toFrame.size)
            self.view.addSubview(picker)
            
            // slide in. Bonus: use our own custom animation util for this.
            RHAnimator.animate(duration: self.showHidePickerDuration, curve: self.pickerAnimationCurve, animation: { (progress : Double) in
                picker.frame.origin = RHAnimator.interpolate(from: fromPosition, to: toFrame.origin, at: progress)
            },completion:{
                self.enableDismissPicker()
            })
        }
    }
    
    var dismissPickerTapRecognizer : UITapGestureRecognizer?
    func enableDismissPicker(){
        // allow dismissing of picker
        if ( self.dismissPickerTapRecognizer == nil )
        {
            self.dismissPickerTapRecognizer = UITapGestureRecognizer( target:self, action:#selector(onTapOutsidePicker) )
        }
        self.view.addGestureRecognizer( self.dismissPickerTapRecognizer! )
    }
    
    func onTapOutsidePicker(){
        self.dismissPicker()
        self.setFunctionGraphVisible(true)
    }
    
    func dismissPicker(){
        // slide picker down, using our own animation util
        self.view.isUserInteractionEnabled = false
        let curve : RHAnimator.Interpolation = self.pickerAnimationCurve
        RHAnimator.animate(duration: self.animationDuration/2, curve: curve, animation: {
            (progress : Double) in
            if let picker = self.animationCurvePicker{
                let yOnscreen = self.view.bounds.height - picker.bounds.height
                picker.frame.origin = CGPoint(x:0, y:yOnscreen + CGFloat(progress) * picker.bounds.height )
            }
        }, completion: {
            self.animationCurvePicker?.removeFromSuperview()
            self.animationCurvePicker = nil
            self.view.isUserInteractionEnabled = true
        })
        
        // remove dismiss gesture recognition
        if (self.dismissPickerTapRecognizer != nil)
        {
            self.view.removeGestureRecognizer(self.dismissPickerTapRecognizer!)
            self.dismissPickerTapRecognizer = nil
        }
    }
    
    // MARK: Animation Duration Slider
    private lazy var durations : [TimeInterval] = {
        [0.1, 0.2, 0.3, 0.4, 0.5, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
    }()
    @IBAction func onAnimationSlider() {
        // snap to nearest defined duration
        let stepCount : Int = self.durations.count-1
        let closestStep : Int = Int(round (self.animationDurationSlider.value * Float(stepCount) ))
        self.animationDurationSlider.value = Float(closestStep) / Float(stepCount)
        self.animationDuration = self.durations[closestStep]
        self.animationDurationLabel.text = "\(self.animationDuration) sec"
    }
    
    // MARK: Function graph
    func configureFunctionGraph(){
        self.graphView.setGridLineInterval(x: 0.1, y: 0.1)
        self.graphView.setMajorGridLineInterval(count: 5)
        self.graphView.gridLineStyle = RHFunctionGraphView.LineStyle(lineWidth: 1.0/self.graphView.contentScaleFactor, color: UIColor.lightGray)
        self.graphView.majorGridLineStyle = RHFunctionGraphView.LineStyle(lineWidth: 2.0/self.graphView.contentScaleFactor, color: UIColor.gray)
    }
    func refreshFunctionGraph(){
        // most animation curves go from (0,0) to (1,1):
        var xMin : CGFloat = 0, yMin : CGFloat = 0
        var xMax : CGFloat = 1, yMax : CGFloat = 1
        let curve : DemoCurve = self.animationCurveEnum
        
        // with some limited exceptions:
        if (curve == .overshoot){
            yMax = 1.1
        }
        else if (curve == .overshoot3){
            yMax = 1.3
        }
        else if (curve == .shake){
            yMin = -1
        }
        
        self.graphView.setDomainAndRange(CGRect(x: xMin, y: yMin, width: xMax-xMin, height: yMax-yMin))
        
        self.graphView.setFunction(self.animationCurve)
    }
    
    func setFunctionGraphVisible(_ visible:Bool){
        // show + hide function graph as picker moves over it. Again, let's use the 
        //  animation util we are demoing
        RHAnimator.animate(duration: self.showHidePickerDuration, curve: self.pickerAnimationCurve, animation:
        {
            (progress: Double) in
            self.graphView.alpha = RHAnimator.interpolate(from: 0.05, to: 1, at: visible ? progress : 1-progress)
        })
    }
}

extension ViewController : UIPickerViewDelegate, UIPickerViewDataSource{
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return self.animationCurveData.count
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return self.animationCurveData[row][titleKey] as? String;
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        self.selectedCurveIndex = row
        self.refreshAnimationCurveButton()
        self.refreshFunctionGraph()
    }
    
    func configureColors(){
        let color : UIColor = self.colorAnimationView.backgroundColor!
        self.animationCurveButton?.tintColor = color
        self.animationDurationStepper?.tintColor = color
        self.animationDurationSlider?.tintColor = color
        self.graphView?.functionLineStyle.color = color
    }
    func refreshAnimationCurveButton(){
        self.animationCurveButton.setTitle(self.animationCurveDescription, for: .normal)
    }
}

extension ViewController : UITextFieldDelegate{
    func refreshDurationTextField(){
        self.animationDurationTextField.text = String(self.animationDuration)
    }
}

