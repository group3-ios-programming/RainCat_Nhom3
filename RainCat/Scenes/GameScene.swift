//
//  GameScene.swift
//  RainCat
//
//  Created by Marc Vandehey on 8/29/16.
//  Copyright © 2016 Thirteen23. All rights reserved.
//

import SpriteKit
import Speech

class GameScene: SceneNode, QuitNavigation, SKPhysicsContactDelegate,SFSpeechRecognizerDelegate, GetFoodNavigation {
    
  var timer = Timer()
  var hihi = true
  private let speechRecognizer = SFSpeechRecognizer(locale: Locale.init(identifier: "en-US"))
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private let audioEngine = AVAudioEngine()
    
  public static var foodIndex = 0
  private var currentRainDropSpawnTime : TimeInterval = 0
  private var rainDropSpawnRate : TimeInterval = 0.5
  private let foodEdgeMargin : CGFloat = 75.0

  private var umbrella : UmbrellaSprite!
  private var cat : CatSprite!
  private var food : FoodSprite?
  private let hud = HudNode()

  private var backgroundNode : BackgroundNode!
  private var groundNode : GroundNode!

  private var currentPalette = ColorManager.sharedInstance.resetPaletteIndex()

  private var catScale : CGFloat = 1
  private var rainScale : CGFloat = 1

  var isMultiplayer = false

  private var umbrellaTouch : UITouch?
  private var catTouch : UITouch?

  override func detachedFromScene() {}

  override func layoutScene(size : CGSize, extras menuExtras: MenuExtras?) {

    timer.invalidate()
    timer = Timer.scheduledTimer(timeInterval: 1.5, target: self, selector: #selector(updateTimer), userInfo: nil, repeats: true)
    speechRecognizer?.delegate = self
    //startRecording()
    if let extras = menuExtras {
      rainScale = extras.rainScale
      catScale = extras.catScale
    }

    isUserInteractionEnabled = true

    anchorPoint = CGPoint()
    var highScore = 0
    if isMultiplayer {
      highScore = UserDefaultsManager.sharedInstance.getClassicMultiplayerHighScore()
    } else {
      highScore = UserDefaultsManager.sharedInstance.getClassicHighScore()
    }

    //Hud Setup
    hud.setup(size: size, palette:  currentPalette, highScore: highScore)
    hud.quitNavigation = self
    hud.getFoodNavigation = self
    addChild(hud)

    //Background Setup
    backgroundNode = BackgroundNode.newInstance(size: size, palette: currentPalette)

    addChild(backgroundNode)

    //Ground Setup
    groundNode = GroundNode.newInstance(size: size, palette: currentPalette)

    addChild(groundNode)
    //World Frame Setup

    var worldFrame = frame
    worldFrame.origin.x -= 100
    worldFrame.origin.y -= 100
    worldFrame.size.height += 200
    worldFrame.size.width += 200

    self.physicsBody = SKPhysicsBody(edgeLoopFrom: worldFrame)
    self.physicsBody?.categoryBitMask = WorldFrameCategory

    //Add Umbrella
    umbrella = UmbrellaSprite(palette: currentPalette)
    umbrella.updatePosition(point: CGPoint(x: frame.midX, y: frame.midY))

    addChild(umbrella)
  }

  override func attachedToScene() {
    //Spawn initial cat and food

    switch catScale {
    case 2:
      umbrella.minimumHeight = size.height * 0.4
    case 3:
      umbrella.minimumHeight = size.height * 0.5
    default:
      umbrella.minimumHeight = size.height * 0.27
    }

    spawnCat()
    spawnFood()
  }

  func quitPressed() {

    if let parent = parent as? Router {
      parent.navigate(to: .MainMenu, extras: MenuExtras(rainScale: 0,
                                                        catScale: 0,
                                                        transition: TransitionExtras(transitionType: .ScaleInLinearTop)))
        if audioEngine.isRunning {
            audioEngine.stop()
            recognitionRequest?.endAudio()
            setAudioSessionDefault()
        }
    }
  }
    func getFoodPressed() {
        
        if audioEngine.isRunning {
            audioEngine.stop()
            recognitionRequest?.endAudio()
            setAudioSessionDefault()
            print("Start Recording")
        } else {
            startRecording()
            print("Stop Recording")
        }
    
    }
    
    func setAudioSessionDefault(){
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(AVAudioSessionCategorySoloAmbient)
            
        } catch {
            print("audioSession properties weren't set because of an error.")
        }
    }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    for touch in touches {
      if groundNode.contains(touch.location(in: self)) {
        //Possible cat touch
        if isMultiplayer && catTouch == nil {
          catTouch = touch
        }
      } else {
        //Possible umbrella touch

        if umbrellaTouch == nil {
          umbrellaTouch = touch

          umbrella.setDestination(destination: (umbrellaTouch?.location(in: self))!)
        }
      }
    }
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    for touch in touches {
      if let uTouch = umbrellaTouch, touch.isEqual(uTouch) {
        umbrella.setDestination(destination: uTouch.location(in: self))
      }
    }
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    for touch in touches {
      if touch.isEqual(umbrellaTouch) {
        umbrellaTouch = nil
      } else if touch.isEqual(catTouch) {
        catTouch = nil
      }
    }
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    for touch in touches {
      if touch.isEqual(umbrellaTouch) {
        umbrellaTouch = nil
      } else if touch.isEqual(catTouch) {
        catTouch = nil
      }
    }
  }

  override func update(dt: TimeInterval) {
    // Called before each frame is rendered
    //hihi = true
    // Update the Spawn Timer
    currentRainDropSpawnTime += dt

    if currentRainDropSpawnTime > rainDropSpawnRate {
      currentRainDropSpawnTime = 0

      spawnRaindrop()
    }

    umbrella.update(deltaTime: dt)

    if let food = childNode(withName: FoodSprite.foodDishName) as? FoodSprite {

      var position = food.position

      if isMultiplayer {
        if catTouch != nil {
          position = catTouch!.location(in: self)
        } else {
          position = cat.position
        }
      }

      cat.update(deltaTime: dt, foodLocation: position)
    }

    cat.movementSpeed = cat.baseMovementSpeed + (cat.baseMovementSpeed * 0.1) * CGFloat(hud.score) / 10.0
  }

  //Spawning Functions

  func spawnRaindrop() {
    for _ in 0...Int(hud.score / 10) {
      let rainDrop = RainDropSprite(scale: rainScale)
      rainDrop.position = CGPoint(x: size.width / 2, y:  size.height / 2)
      rainDrop.addPhysics()
      rainDrop.zPosition = 2


      var randomPosition = CGFloat(arc4random())
      randomPosition = randomPosition.truncatingRemainder(dividingBy: size.width)
      rainDrop.position = CGPoint(x: randomPosition, y: size.height)

      //Raindrop fun

      if hud.score > 10 && arc4random() % 10 == 0 {
        rainDrop.yScale = -1
      }

      if hud.score > 20 && arc4random() % 10 == 0 {
        rainDrop.physicsBody?.velocity.dx = (CGFloat(arc4random()).truncatingRemainder(dividingBy: 4) + 1.0) * 100
        rainDrop.physicsBody?.velocity.dx *= arc4random() % 2 == 0 ? -1 : 1
        rainDrop.zPosition = 4
        rainDrop.color = currentPalette.umbrellaBottomColor
      }

      if hud.score > 30 && arc4random() % 10 == 0 {
        rainDrop.setScale(rainScale * 2)
        rainDrop.physicsBody?.density = 1000
      }

      rainDrop.physicsBody?.linearDamping = CGFloat(arc4random()).truncatingRemainder(dividingBy: 100) / 100

      addChild(rainDrop)
    }
  }

  func spawnCat() {
    if let currentCat = cat, children.contains(currentCat) {
      cat.removeFromParent()
      cat.removeAllActions()
      cat.physicsBody = nil
    }

    cat = CatSprite.newInstance()

    if isMultiplayer {
      cat.addDash()
    }

    cat.setScale(0.5)
    cat.position = CGPoint(x: umbrella.position.x, y: umbrella.position.y + umbrella.getHeight() / 2)
    cat.run(SKAction.scale(to: catScale, duration: 0.3))

    hud.resetPoints()
    addChild(cat)
  }

  func spawnFood() {
    var containsFood = false

    for child in children {
      if child.name == FoodSprite.foodDishName {
        containsFood = true
        break
      }
    }

    if !containsFood {
      GameScene.foodIndex = FoodSprite.foodIndex
      food = FoodSprite.newInstance(palette: currentPalette)
      var randomPosition : CGFloat = CGFloat(arc4random())
      randomPosition = randomPosition.truncatingRemainder(dividingBy: size.width - foodEdgeMargin * 2)
      randomPosition += foodEdgeMargin
        
      print(randomPosition)
      food?.position = CGPoint(x: randomPosition, y: size.height)
      food?.physicsBody?.friction = 100
      addChild(food!)
    }
  }

  //Contact Functions

  func didBegin(_ contact: SKPhysicsContact) {
    if contact.bodyA.categoryBitMask == FoodCategory || contact.bodyB.categoryBitMask == FoodCategory {
      handleFoodHit(contact: contact)
    }

    if contact.bodyA.categoryBitMask == CatCategory || contact.bodyB.categoryBitMask == CatCategory {
      handleCatCollision(contact: contact)
      return
    }

    if contact.bodyA.categoryBitMask == RainDropCategory {
      contact.bodyA.node?.physicsBody?.collisionBitMask = 0
      contact.bodyA.node?.physicsBody?.categoryBitMask = 0
    } else if contact.bodyB.categoryBitMask == RainDropCategory {
      contact.bodyB.node?.physicsBody?.collisionBitMask = 0
      contact.bodyB.node?.physicsBody?.categoryBitMask = 0
    }

    if contact.bodyA.categoryBitMask == WorldFrameCategory {
      contact.bodyB.node?.removeFromParent()
      contact.bodyB.node?.physicsBody = nil
      contact.bodyB.node?.removeAllActions()
    } else if contact.bodyB.categoryBitMask == WorldFrameCategory {
      contact.bodyA.node?.removeFromParent()
      contact.bodyA.node?.physicsBody = nil
      contact.bodyA.node?.removeAllActions()
    }
  }

  func handleCatCollision(contact: SKPhysicsContact) {
    var otherBody : SKPhysicsBody

    if contact.bodyA.categoryBitMask == CatCategory {
      otherBody = contact.bodyB
    } else {
      otherBody = contact.bodyA
    }

    switch otherBody.categoryBitMask {
    case RainDropCategory:

      if let parent = parent as? WorldManager {
        parent.tempPauseScene(duration: 0.1)
      }

      cat.hitByRain()
      hud.resetPoints()
      resetColorPalette()

      rainDropSpawnRate = 0.5
    case WorldFrameCategory:
      spawnCat()
    case FloorCategory:
      cat.isGrounded = true
    default:
      cat.callFoodName()
    }
  }

  override func getGravity() -> CGVector {
    return CGVector(dx: 0, dy: -7.8)
  }

  func handleFoodHit(contact: SKPhysicsContact) {
    var otherBody : SKPhysicsBody
    var foodBody : SKPhysicsBody

    if(contact.bodyA.categoryBitMask == FoodCategory) {
      otherBody = contact.bodyB
      foodBody = contact.bodyA
    } else {
      otherBody = contact.bodyA
      foodBody = contact.bodyB
    }

    switch otherBody.categoryBitMask {
    case CatCategory:
      hud.addPoint()

      if isMultiplayer {
        UserDefaultsManager.sharedInstance.updateClassicMultiplayerHighScore(highScore: hud.score)
      } else {
        UserDefaultsManager.sharedInstance.updateClassicHighScore(highScore: hud.score)
      }

      if hud.score % 5 == 0 {
        updateColorPalette()
        rainDropSpawnRate *= 0.95
      }

      //Stronger gravity the higher the score
      let dy : CGFloat = -7.8 - CGFloat(hud.score % 10)
      var dx : CGFloat = 0.0

      //Update Gravity here
      if hud.score > 50  {
        dx = 2.0
      }

      if let parent = parent as? WorldManager {
        parent.updateGravity(vector: CGVector(dx: dx, dy: dy))
      }

      fallthrough
    case WorldFrameCategory:
      foodBody.node?.removeFromParent()
      foodBody.node?.physicsBody = nil

      food = nil

      spawnFood()

    default:
      print("something else touched the food")
    }
  }

  func updateColorPalette() {
    currentPalette = ColorManager.sharedInstance.getNextColorPalette()

    for node in children {
      if let node = node as? Palettable {
        node.updatePalette(palette: currentPalette)
      }
    }
  }

  func resetColorPalette() {
    currentPalette = ColorManager.sharedInstance.resetPaletteIndex()
    
    for node in children {
      if let node = node as? Palettable {
        node.updatePalette(palette: currentPalette)
      }
    }
  }
  
  deinit {
    print("game scene destroyed")
  }
    
    func startRecording() {
        
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(AVAudioSessionCategoryRecord)
            try audioSession.setMode(AVAudioSessionModeMeasurement)
            try audioSession.setActive(true, with: .notifyOthersOnDeactivation)
        } catch {
            print("audioSession properties weren't set because of an error.")
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let inputNode = audioEngine.inputNode else {
            fatalError("Audio engine has no input node")
        }
        
        guard let recognitionRequest = recognitionRequest else {
            fatalError("Unable to create an SFSpeechAudioBufferRecognitionRequest object")
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest, resultHandler: { (result, error) in
            
            var isFinal = false
            if let result = result{
                var lastString = ""
                let bestString = result.bestTranscription.formattedString.lowercased()
                for i in result.bestTranscription.segments {
                    let indexTo = bestString.index(bestString.startIndex, offsetBy: i.substringRange.location)
                    lastString = bestString.substring(from: indexTo)
                    
                }
                
                isFinal = result.isFinal
                self.checkFruit(resultString: lastString)
                print(lastString)
                
                
                
            }
            
            if error != nil || isFinal {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                
                self.recognitionRequest = nil
                self.recognitionTask = nil
                self.setAudioSessionDefault()
                //self.startRecording()
                //self.microphoneButton.isEnabled = true
            }
        })
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer, when) in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
        } catch {
            print("audioEngine couldn't start because of an error.")
        }
        //textView.text = "Say something, I'm listening!"
        
        
    }
    func checkFruit(resultString: String) {
        var x = cat.position.x
        if CatSprite.right {
            x += 80
        }
        if CatSprite.left {
            x -= 150
        }
        if hihi {
            switch resultString {
            case "avocado":
                let food = FoodSprite.newInstanceCatFood(palette: currentPalette, foodName: resultString)
                food.position = CGPoint(x: x, y: 200)
                hihi = false
                addChild(food)
            case "banana":
                let food = FoodSprite.newInstanceCatFood(palette: currentPalette, foodName: resultString);
                food.position = CGPoint(x: x, y: 200)
                hihi = false
                addChild(food)
            case "carrot":
                let food = FoodSprite.newInstanceCatFood(palette: currentPalette, foodName: resultString)
                food.position = CGPoint(x: x, y: 200)
                hihi = false
                addChild(food)
            case "grape":
                let food = FoodSprite.newInstanceCatFood(palette: currentPalette, foodName: resultString)
                food.position = CGPoint(x: x, y: 200)
                hihi = false
                addChild(food)
            case "lemon":
                let food = FoodSprite.newInstanceCatFood(palette: currentPalette, foodName: resultString)
                food.position = CGPoint(x: x, y: 200)
                addChild(food)
            case "mango":
                let food = FoodSprite.newInstanceCatFood(palette: currentPalette, foodName: resultString)
                food.position = CGPoint(x: x, y: 200)
                hihi = false
                addChild(food)
            case "orange":
                let food = FoodSprite.newInstanceCatFood(palette: currentPalette, foodName: resultString)
                food.position = CGPoint(x: x, y: 200)
                hihi = false
                addChild(food)
            case "papaya":
                let food = FoodSprite.newInstanceCatFood(palette: currentPalette, foodName: resultString)
                food.position = CGPoint(x: x, y: 200)
                hihi = false
                addChild(food)
            case "pineapple":
                let food = FoodSprite.newInstanceCatFood(palette: currentPalette, foodName: resultString)
                food.position = CGPoint(x: x, y: 200)
                hihi = false
                addChild(food)
            case "strwberry":
                let food = FoodSprite.newInstanceCatFood(palette: currentPalette, foodName: resultString)
                food.position = CGPoint(x: x, y: 200)
                hihi = false
                addChild(food)
            default: break
            }
        }
        
    }
    
    public func updateTimer() {
        hihi = true
    }
    
    
}
