//
//  ViewController.swift
//  ImageDetection
//
//  Created by Alok Irde on 10/16/16.
//  Copyright © 2016 Alok Irde. All rights reserved.
//

import UIKit
import SwiftyJSON


class ViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    //MARK: Dynamic Animation Implementation
    fileprivate var animator: UIDynamicAnimator?
    fileprivate var gravity: UIGravityBehavior?
    fileprivate var collider: UICollisionBehavior?
    fileprivate var bloomView: UITextView?
    
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var showImageButton: UIButton!
    @IBAction func launchImagePicker(_ sender: AnyObject) {
        let alert = UIAlertController(title: "Select Image Source", message: nil, preferredStyle: .actionSheet)
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            if UIImagePickerController.isCameraDeviceAvailable(.front) {
                let camera = UIAlertAction(title: "Front Camera", style: .default, handler:nil)
                alert.addAction(camera)
            } else {
                let camera = UIAlertAction(title: "Rear Camera", style: .default, handler: nil)
                alert.addAction(camera)
            }
        }
        if UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
            let photoLibrary = UIAlertAction(title: "Photo Library", style: .default, handler: { (action) in
                // do something on select of photo library
                self.clearAllBehaviors()
                self.openPicker(for: .photoLibrary)
            })
            alert.addAction(photoLibrary)
        }

        self.present(alert, animated: true) { 
            print("Presenting action sheet for selection")
        }
    }
    
    fileprivate func clearAllBehaviors() {
        gravity = UIGravityBehavior()
        collider = UICollisionBehavior()
        bloomView?.removeFromSuperview()
        activateBloom()
    }
    
    private var ImageAnalyzeQueue = DispatchQueue(label: "com.imagedetection.googlevisionapi.q")
    private var API_KEY = "YOUR API KEY GOES HERE"
    
    fileprivate func openPicker(for sourceType: UIImagePickerControllerSourceType) {
        let imagePicker = UIImagePickerController()
        imagePicker.modalPresentationStyle = .currentContext
        imagePicker.sourceType = sourceType
        imagePicker.delegate = self
        imagePicker.modalPresentationStyle = (sourceType == .camera) ? .fullScreen : .popover
        self.present(imagePicker, animated: true, completion: nil)
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        animator = UIDynamicAnimator(referenceView: self.view)
        gravity = UIGravityBehavior()
        collider = UICollisionBehavior()
        activateBloom()
    }
    
    fileprivate func activateBloom() {
        bloomView = UITextView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        bloomView?.center = CGPoint(x: self.view.center.x, y: 0)
        bloomView?.backgroundColor = UIColor.clear
        view.addSubview(bloomView!)
    }
    
    fileprivate func enableConstraints() {
        let margins = self.view.layoutMarginsGuide
        
        // Enable constraints on imageView
        imageView.leadingAnchor.constraint(lessThanOrEqualTo: margins.leadingAnchor, constant: 0)
        imageView.trailingAnchor.constraint(lessThanOrEqualTo: margins.trailingAnchor, constant: 0)
        imageView.topAnchor.constraint(lessThanOrEqualTo: margins.topAnchor, constant: 0)
        imageView.bottomAnchor.constraint(lessThanOrEqualTo: showImageButton.topAnchor, constant: 10)
        imageView.centerXAnchor.constraint(equalTo: self.view.centerXAnchor)
        
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    //MARK: UIImagePickerControllerDelegate methods
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        if let image = info[UIImagePickerControllerOriginalImage] as? UIImage {
            imageView.image = image
            analyze(image)
        }
        picker.dismiss(animated: true, completion: nil)
    }
    
    
    fileprivate func encode(image: UIImage) -> String? {
        if let imagedata = UIImagePNGRepresentation(image)  {
            if imagedata.count > 2097152 {
                let oldsize = image.size
                let newsize = CGSize(width: 800, height: oldsize.height / oldsize.width * 800)
                if let newimagedata = resize(image: image, to: newsize) {
                    return newimagedata.base64EncodedString(options: .endLineWithCarriageReturn)
                } else {
                    return nil
                }
            } else {
                return imagedata.base64EncodedString(options: .endLineWithCarriageReturn)
            }
        }
        return nil
    }
    
    fileprivate func resize(image: UIImage, to size: CGSize) -> Data? {
        UIGraphicsBeginImageContext(size)
        var resizedImage: Data? = nil
        image.draw(in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        if let newImage = UIGraphicsGetImageFromCurrentImageContext() {
            resizedImage = UIImagePNGRepresentation(newImage)
        }
        UIGraphicsEndImageContext()
        return resizedImage
    }
    
    fileprivate func analyze(_ image: UIImage) {
        ImageAnalyzeQueue.async {
            if let encodedString = self.encode(image: image) {
                self.annotate(content: encodedString)
            }
        }
    }
    
    
    
    fileprivate func annotate(content: String) {
        if let url = URL(string: "https://vision.googleapis.com/v1/images:annotate?key=\(API_KEY)") {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            let jsonRequest: [String: Any] = [
                "requests": [
                    "image": ["content": content],
                    "features": [
                        ["type": "LOGO_DETECTION", "maxResults": 5],
                        ["type": "LABEL_DETECTION", "maxResults": 5],
                        ["type": "TEXT_DETECTION", "maxResults": 5],
                        ["type": "LANDMARK_DETECTION", "maxResults": 5]
                        
                    ]
                ]]
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: jsonRequest, options: [])
                let session = URLSession.shared
                let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
                    if error != nil {
                    } else if let data = data {
                        self.analyzeResults(data)
                    }
                })
                task.resume()
            } catch _ {}
        }
    }
    
    fileprivate func analyzeResults(_ data: Data) {
        let json = JSON(data: data)
        let errorObj: JSON = json["error"]
        
        if (errorObj.dictionaryValue != [:]) {
            
        } else {
            DispatchQueue.main.async {
                if let animator = self.animator, let gravity = self.gravity, let collider = self.collider, let bloomView = self.bloomView, let button = self.showImageButton, let imageView = self.imageView {
                    
                    let responses: JSON = json["responses"][0]
                    let labelAnnotations = responses["labelAnnotations"]
                    var labelInfo = ""
                    for annotations in labelAnnotations {
                        labelInfo = labelInfo + "\n\(annotations.1["description"]) = \(annotations.1["score"])"
                    }
                    
                    bloomView.text = labelInfo
                    bloomView.backgroundColor = .gray
                    bloomView.alpha = 0.5
                    bloomView.textColor = .red
                    bloomView.font = UIFont.boldSystemFont(ofSize: 16)
                    gravity.addItem(bloomView)
                    collider.addItem(bloomView)
                    collider.translatesReferenceBoundsIntoBoundary = true
                    collider.addBoundary(withIdentifier: "barrier" as NSCopying, from:CGPoint(x: 0, y: imageView.frame.maxY + 100) , to: CGPoint(x: button.frame.width, y: imageView.frame.maxY + 100))
                    animator.addBehavior(gravity)
                    animator.addBehavior(collider)
                }
            }
        }
    }
}

