// Copyright 2021 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
import UIKit
import SnapKit
import BraveShared
import Preferences
import Shared
import BraveCore
import BraveUI
import SafariServices
import DesignSystem

public class TimidWelcomeViewController: UIViewController {

    private var state: WelcomeViewCalloutState?
    private let p3aUtilities: BraveP3AUtils

    public convenience init(p3aUtilities: BraveP3AUtils) {
        self.init(state: .loading, p3aUtilities: p3aUtilities)
    }

    public init(state: WelcomeViewCalloutState?, p3aUtilities: BraveP3AUtils) {
        self.state = state
        self.p3aUtilities = p3aUtilities
        super.init(nibName: nil, bundle: nil)

        self.transitioningDelegate = self
        self.modalPresentationStyle = .fullScreen
        self.loadViewIfNeeded()
        setupDefaultState()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        view.addConstraints([
            view.topAnchor.constraint(equalTo: scrollView.topAnchor),
            view.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor)
        ])

        let stackView = UIStackView(arrangedSubviews: [])
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.distribution = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)
        view.addConstraints([
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stackView.heightAnchor.constraint(greaterThanOrEqualTo: view.heightAnchor, multiplier: 0.9)
        ])

        let image = UIImage(named: "onboarding_logo", in: .module, compatibleWith: nil)!
        let imageView = UIImageView(image: image)
        
        let label = UILabel()
        label.numberOfLines = 0
        label.textColor = .white
        label.textAlignment = .center
        label.font = UIFont.boldSystemFont(ofSize: 18)
        label.text = "Timid Browser is fork of mighty Brave Browser. You love brave browser, you would love to have multiple instances on your phone for compartmentalization, that’s why Timid Browser exists. 🖖"

        let button = UIButton(type: .roundedRect)
        button.backgroundColor = .systemBlue
        button.setTitle("LFG!", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.layer.masksToBounds = true
        button.addTarget(self, action: #selector(close), for: .touchUpInside)

        [imageView, label, button].forEach {
            stackView.addArrangedSubview($0)
        }
        
        imageView.contentMode = .scaleAspectFit
        view.addConstraints([
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: 1.2),
            button.heightAnchor.constraint(equalToConstant: 48),
        ])
    }

    func setupDefaultState() {
        self.p3aUtilities.isP3AEnabled = false
        self.p3aUtilities.isNoticeAcknowledged = true
        Preferences.Onboarding.basicOnboardingCompleted.value = OnboardingState.completed.rawValue
        Preferences.Onboarding.basicOnboardingDefaultBrowserSelected.value = false
        Preferences.Onboarding.basicOnboardingProgress.value = OnboardingProgress.rewards.rawValue
    }

    @objc private func close() {
        var presenting: UIViewController = self
        while true {
            if let presentingController = presenting.presentingViewController {
                presenting = presentingController
                continue
            }

            if let presentingController = presenting as? UINavigationController,
               let topController = presentingController.topViewController {
                presenting = topController
            }

            break
        }

        Preferences.Onboarding.basicOnboardingProgress.value = OnboardingProgress.newTabPage.rawValue
        presenting.dismiss(animated: false, completion: nil)
    }
}

extension TimidWelcomeViewController: UIViewControllerTransitioningDelegate {
    public func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return WelcomeAnimator(isPresenting: true)
    }

    public func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return WelcomeAnimator(isPresenting: false)
    }
}

// Disabling orientation changes
extension TimidWelcomeViewController {
    public override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    public override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .portrait
    }

    public override var shouldAutorotate: Bool {
        return false
    }
}



