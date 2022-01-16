//
//  PlumViewController.swift
//  Nuke-Avif-Plugin
//
//  Created by murakami on 05/27/2021.
//  Copyright (c) 2021 murakami. All rights reserved.
//

import UIKit
import Nuke
import RxSwift
import RxCocoa

class PlumViewController: UIViewController {
    @IBOutlet var imageView: UIImageView!
    @IBOutlet var profile: UISegmentedControl!
    @IBOutlet var bitDepth: UISegmentedControl!
    @IBOutlet var format: UISegmentedControl!
    @IBOutlet var monochrome: UISegmentedControl!
    @IBOutlet var alpha: UISegmentedControl!
    @IBOutlet var notFoundLabel: UILabel!
    
    private let disposeBag = DisposeBag()
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        Observable
            .combineLatest([profile, bitDepth, format, monochrome, alpha].map { $0.rx.selectedSegmentIndex })
            .subscribe(onNext: { [weak self] array in
                let profile = ["0", "1", "2"][array[0]]
                let bitDepth = ["8", "10", "12"][array[1]]
                let format = ["yuv420", "yuv422", "yuv444"][array[2]]
                let monochrome = ["", ".monochrome"][array[3]]
                let alpha = [".alpha-full", ".alpha-limited"][array[4]]
                
                let url = URL(string: "https://raw.githubusercontent.com/link-u/avif-sample-images/master/plum-blossom-large.profile\(profile).\(bitDepth)bpc.\(format)\(alpha)\(monochrome).avif")!
                print(url.absoluteString)
                guard let imageView = self?.imageView else { return }
                Nuke.loadImage(with: url, into: imageView) { result in
                    if case let .failure(error) = result, case .dataLoadingFailed = error {
                        self?.notFoundLabel.isHidden = false
                    } else {
                        self?.notFoundLabel.isHidden = true
                    }
                }
            })
            .disposed(by: disposeBag)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

}

