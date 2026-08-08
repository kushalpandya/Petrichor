//
// LibraryManager class extension
//
// How Discover mixes candidate rows into a carousel. Pure functions over rows LMDiscover
// has already fetched: no database access, no published state.
//

import Foundation

extension LibraryManager {
    // MARK: - Selection

    /// Interleaves in-rotation and neglected picks, giving the odd slot to in-rotation.
    static func selectFeatured(
        rotation: [DiscoverEntityRow],
        neglected: [DiscoverEntityRow]
    ) -> [DiscoverEntityRow] {
        let target = DiscoverConfiguration.carouselItemCount
        let rotationTarget = (target + 1) / 2
        let neglectedTarget = target / 2
        var hot = selectRoundRobin(rotation, target: rotationTarget)
        var cold = selectRoundRobin(neglected, target: neglectedTarget, excluding: Set(hot.map(\.ref)))

        if hot.count < rotationTarget {
            let taken = Set(hot.map(\.ref)).union(cold.map(\.ref))
            cold += selectRoundRobin(neglected, target: target - hot.count - cold.count, excluding: taken)
        } else if cold.count < neglectedTarget {
            let taken = Set(hot.map(\.ref)).union(cold.map(\.ref))
            hot += selectRoundRobin(rotation, target: target - hot.count - cold.count, excluding: taken)
        }

        var result: [DiscoverEntityRow] = []
        var hotIndex = 0
        var coldIndex = 0
        while result.count < target && (hotIndex < hot.count || coldIndex < cold.count) {
            if hotIndex < hot.count {
                result.append(hot[hotIndex])
                hotIndex += 1
            }
            if result.count < target, coldIndex < cold.count {
                result.append(cold[coldIndex])
                coldIndex += 1
            }
        }
        return result
    }

    /// Cycles `carouselOrder`, taking each kind's next-best candidate and skipping
    /// exhausted kinds, so a library with no playlists still fills every slot. Each kind's
    /// rank order is preserved within its bucket.
    static func selectRoundRobin(
        _ candidates: [DiscoverEntityRow],
        target: Int,
        excluding: Set<DiscoverEntityRef> = []
    ) -> [DiscoverEntityRow] {
        guard target > 0 else { return [] }

        var buckets: [DiscoverEntityKind: [DiscoverEntityRow]] = [:]
        for row in candidates where !excluding.contains(row.ref) {
            buckets[row.ref.kind, default: []].append(row)
        }

        var result: [DiscoverEntityRow] = []
        var taken = excluding
        var cursors: [DiscoverEntityKind: Int] = [:]

        while result.count < target {
            var addedThisPass = false

            for kind in DiscoverEntityKind.carouselOrder {
                guard result.count < target else { break }
                guard let bucket = buckets[kind] else { continue }

                var index = cursors[kind] ?? 0
                while index < bucket.count && taken.contains(bucket[index].ref) {
                    index += 1
                }
                cursors[kind] = index
                guard index < bucket.count else { continue }

                let row = bucket[index]
                result.append(row)
                taken.insert(row.ref)
                cursors[kind] = index + 1
                addedThisPass = true
            }

            if !addedThisPass { break }
        }

        return result
    }
}
