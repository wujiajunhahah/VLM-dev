//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2025 Apple Inc. All Rights Reserved.
//

import SwiftUI
import Photos

struct EmojiStatsView: View {
    let store: EmojiLogStore
    @State private var assets: [PHAsset] = []

    var body: some View {
        List {
            Section("今天") {
                ForEach(store.groupedByHour(), id: \.hour) { pair in
                    HStack(alignment: .center) {
                        Text(String(format: "%02d:00", pair.hour))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .leading)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                if pair.emojis.isEmpty {
                                    Text("—").foregroundStyle(.tertiary)
                                } else {
                                    ForEach(Array(pair.emojis.enumerated()), id: \.offset) { _, e in
                                        Text(e).font(.title3)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Section("空间相册预览") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(assets, id: \.localIdentifier) { asset in
                            AssetThumbnail(asset: asset)
                                .frame(width: 120, height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Emoji 统计")
        .task { await loadAssets() }
    }
}

#Preview {
    NavigationStack { EmojiStatsView(store: EmojiLogStore()) }
}

private struct AssetThumbnail: View {
    let asset: PHAsset
    @State private var image: UIImage? = nil

    var body: some View {
        ZStack {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { ProgressView() }
        }
        .task { await fetch() }
    }

    private func fetch() async {
        await withCheckedContinuation { cont in
            let manager = PHImageManager.default()
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isSynchronous = false
            manager.requestImage(for: asset, targetSize: CGSize(width: 240, height: 240), contentMode: .aspectFill, options: options) { img, _ in
                self.image = img
                cont.resume()
            }
        }
    }
}

extension EmojiStatsView {
    func loadAssets() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { return }
        let fetch = PHAsset.fetchAssets(with: .image, options: nil)
        var list: [PHAsset] = []
        fetch.enumerateObjects { asset, _, _ in list.append(asset) }
        // 取最近的 30 张
        self.assets = Array(list.suffix(30)).reversed()
    }
}


