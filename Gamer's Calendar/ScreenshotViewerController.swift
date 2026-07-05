
import UIKit

/// Полноэкранный просмотр скриншотов: листание свайпом, зум щипком
/// и двойным тапом, закрытие крестиком или свайпом вниз.
class ScreenshotViewerController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {

    private let urls: [URL]
    private let pageControl = UIPageControl()

    init(urls: [URL], startIndex: Int) {
        self.urls = urls
        super.init(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [.interPageSpacing: 16]
        )

        modalPresentationStyle = .fullScreen
        dataSource = self
        delegate = self
        setViewControllers([makePage(at: startIndex)], direction: .forward, animated: false)
        pageControl.currentPage = startIndex
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        let closeButton = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: config), for: .normal)
        closeButton.tintColor = .white.withAlphaComponent(0.8)
        closeButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16)
        ])

        pageControl.numberOfPages = urls.count
        pageControl.hidesForSinglePage = true
        pageControl.isUserInteractionEnabled = false
        pageControl.pageIndicatorTintColor = .white.withAlphaComponent(0.3)
        pageControl.currentPageIndicatorTintColor = .white

        pageControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageControl)

        NSLayoutConstraint.activate([
            pageControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageControl.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8)
        ])

        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeDown))
        swipeDown.direction = .down
        view.addGestureRecognizer(swipeDown)
    }

    @objc private func handleSwipeDown() {
        // Не закрываем, если пользователь просто двигает приближенный скриншот.
        if let page = viewControllers?.first as? ZoomableScreenshotViewController, page.isZoomed {
            return
        }
        dismiss(animated: true)
    }

    private func makePage(at index: Int) -> ZoomableScreenshotViewController {
        ZoomableScreenshotViewController(url: urls[index], index: index)
    }

    // MARK: - UIPageViewControllerDataSource

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? ZoomableScreenshotViewController, page.index > 0 else {
            return nil
        }
        return makePage(at: page.index - 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? ZoomableScreenshotViewController, page.index < urls.count - 1 else {
            return nil
        }
        return makePage(at: page.index + 1)
    }

    // MARK: - UIPageViewControllerDelegate

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        if completed, let page = viewControllers?.first as? ZoomableScreenshotViewController {
            pageControl.currentPage = page.index
        }
    }

}

/// Одна страница просмотрщика: скриншот с зумом.
class ZoomableScreenshotViewController: UIViewController, UIScrollViewDelegate {

    let index: Int

    var isZoomed: Bool {
        scrollView.zoomScale > scrollView.minimumZoomScale
    }

    private let url: URL
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .large)

    init(url: URL, index: Int) {
        self.url = url
        self.index = index
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.delegate = self
        view.addSubview(scrollView)

        imageView.frame = scrollView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.contentMode = .scaleAspectFit
        scrollView.addSubview(imageView)

        spinner.color = .white
        spinner.center = view.center
        spinner.autoresizingMask = [.flexibleTopMargin, .flexibleBottomMargin, .flexibleLeftMargin, .flexibleRightMargin]
        view.addSubview(spinner)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        loadImage()
    }

    private func loadImage() {
        if let cached = ImageCache.shared.image(for: url) {
            imageView.image = cached
            return
        }

        spinner.startAnimating()

        Task {
            let image = await ImageCache.shared.loadImage(from: url)
            spinner.stopAnimating()
            imageView.image = image
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        } else {
            // Приближаем к точке, по которой тапнули.
            let point = gesture.location(in: imageView)
            let zoomScale: CGFloat = 2.5
            let size = CGSize(
                width: scrollView.bounds.width / zoomScale,
                height: scrollView.bounds.height / zoomScale
            )
            let rect = CGRect(
                origin: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2),
                size: size
            )
            scrollView.zoom(to: rect, animated: true)
        }
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

}
