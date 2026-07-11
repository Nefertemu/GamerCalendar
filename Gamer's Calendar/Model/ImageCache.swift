import UIKit

/// Простой кэш загруженных обложек, чтобы не тянуть одну и ту же картинку
/// по сети повторно при переиспользовании ячеек во время скролла.
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, UIImage>()

    /// Сессия с дисковым кэшем: картинки не скачиваются заново после перезапуска.
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 256 * 1024 * 1024)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: configuration)
    }()

    private init() {}

    func image(for url: URL) -> UIImage? {
        guard let image = cache.object(forKey: url as NSURL) else { return nil }
        if Self.isLikelyPlaceholder(image) {
            cache.removeObject(forKey: url as NSURL)
            return nil
        }
        return image
    }

    func loadImage(from url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }

        guard let (data, _) = try? await session.data(from: url),
              let image = UIImage(data: data) else {
            return nil
        }

        cache.setObject(image, forKey: url as NSURL)
        return image
    }

    /// Горизонтальный постер игры. Среди артов выбирается самый большой
    /// по весу файл (HEAD-запросы): детализированный постер с логотипом
    /// весит в разы больше пустышек и тёмных заглушек. Фолбэки — скриншот
    /// и обложка через обычную цепочку кандидатов.
    func loadPoster(for game: GamesStorage, includesPortraitFallback: Bool = true) async -> UIImage? {
        let artworks = game.artworkURLs ?? []

        // Выбранный ранее арт уже в памяти — берём его.
        for url in artworks {
            if let cached = image(for: url) {
                return cached
            }
        }

        if let best = await richestURL(among: artworks),
           let image = await loadImage(fromCandidates: [best]) {
            return image
        }

        let fallbackCandidates = includesPortraitFallback
            ? game.posterCandidates
            : game.posterCandidates.filter { $0 != game.coverURL }
        return await loadImage(fromCandidates: fallbackCandidates)
    }

    /// URL самого детализированного арта. CDN IGDB не отдаёт размер файла
    /// в заголовках, поэтому скачиваем миниатюры (t_thumb, пара КБ каждая)
    /// и сравниваем их «содержательность»: вес файла со штрафом за белый фон.
    /// Пустышки весят копейки, а карточки-логотипы на белом фоне проигрывают
    /// настоящим постерам, даже если их миниатюра чуть тяжелее.
    private func richestURL(among urls: [URL]) async -> URL? {
        guard !urls.isEmpty else { return nil }

        return await withTaskGroup(of: (url: URL, score: Int)?.self) { group in
            for url in urls {
                group.addTask { [session] in
                    let thumbPath = url.absoluteString.replacingOccurrences(of: "/t_720p/", with: "/t_thumb/")
                    guard let thumbURL = URL(string: thumbPath),
                          let (data, _) = try? await session.data(from: thumbURL),
                          data.count > 1000 else { return nil }

                    return (url, Self.contentScore(ofThumb: data))
                }
            }

            var best: (url: URL, score: Int)?
            for await candidate in group {
                if let candidate, candidate.score > (best?.score ?? 0) {
                    best = candidate
                }
            }
            return best?.url
        }
    }

    /// Оценка «содержательности» миниатюры: вес файла, умноженный на долю
    /// небелых пикселей. Карточка-логотип на белом фоне получает низкий балл.
    private static func contentScore(ofThumb data: Data) -> Int {
        guard let cgImage = UIImage(data: data)?.cgImage else { return 0 }

        let width = 48
        let height = 28
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return data.count }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var whiteCount = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            if pixels[index] > 245, pixels[index + 1] > 245, pixels[index + 2] > 245 {
                whiteCount += 1
            }
        }

        let whiteFraction = Double(whiteCount) / Double(width * height)
        return Int(Double(data.count) * (1.0 - whiteFraction))
    }

    /// Первая «содержательная» картинка из кандидатов. У IGDB встречаются
    /// пустые белые артворки — такие JPEG весят считаные килобайты,
    /// отсекаем их по размеру файла и берём следующий вариант.
    /// Приоритет строгий: закэшированный менее приоритетный кандидат не должен
    /// обгонять более приоритетный (сетке нужна именно вертикальная обложка).
    func loadImage(fromCandidates urls: [URL]) async -> UIImage? {
        for url in urls {
            if let cached = image(for: url) {
                return cached
            }

            guard let (data, _) = try? await session.data(from: url),
                  data.count > 6000,
                  let image = UIImage(data: data),
                  !Self.isLikelyPlaceholder(image) else { continue }

            cache.setObject(image, forKey: url as NSURL)
            return image
        }

        return nil
    }

    /// Первая валидная альбомная картинка. Используется там, где портретная
    /// обложка с размытыми полями выглядит как сломанный белый прямоугольник.
    func loadLandscapeImage(fromCandidates urls: [URL]) async -> UIImage? {
        for url in urls {
            if let cached = image(for: url), Self.isLandscape(cached) {
                return cached
            }

            guard let (data, _) = try? await session.data(from: url),
                  data.count > 6000,
                  let image = UIImage(data: data),
                  Self.isLandscape(image),
                  !Self.isLikelyPlaceholder(image) else { continue }

            cache.setObject(image, forKey: url as NSURL)
            return image
        }

        return nil
    }

    private static func isLandscape(_ image: UIImage) -> Bool {
        image.size.width / max(image.size.height, 1) >= 1.25
    }

    private static func isLikelyPlaceholder(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }

        let width = 48
        let height = 28
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var brightNeutralCount = 0
        var centerBrightNeutralCount = 0
        var centerPixelCount = 0
        var brightNeutralByColumn = [Int](repeating: 0, count: width)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let pixel = index / 4
            let x = pixel % width
            let red = Int(pixels[index])
            let green = Int(pixels[index + 1])
            let blue = Int(pixels[index + 2])
            let maxChannel = max(red, green, blue)
            let minChannel = min(red, green, blue)
            let isBrightNeutral = maxChannel > 205 && (maxChannel - minChannel) < 45
            let isCenterStrip = x >= 14 && x <= 33

            if isBrightNeutral {
                brightNeutralCount += 1
                brightNeutralByColumn[x] += 1
            }
            if isCenterStrip {
                centerPixelCount += 1
                if isBrightNeutral {
                    centerBrightNeutralCount += 1
                }
            }
        }

        let brightNeutralFraction = Double(brightNeutralCount) / Double(width * height)
        let centerBrightNeutralFraction = Double(centerBrightNeutralCount) / Double(max(centerPixelCount, 1))
        let centerColumns = brightNeutralByColumn[14...33]
        let solidCenterColumns = centerColumns.filter { Double($0) / Double(height) > 0.82 }.count

        // IGDB sometimes returns placeholder covers: either almost all white,
        // or a solid bright vertical strip with muted side colors.
        return brightNeutralFraction > 0.58 || centerBrightNeutralFraction > 0.52 || solidCenterColumns >= 7
    }
}
