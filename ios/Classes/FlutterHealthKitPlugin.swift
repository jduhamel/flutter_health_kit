import Flutter
import HealthKit
import UIKit
import os

public class FlutterHealthKitPlugin: NSObject, FlutterPlugin {
    let binaryMessenger: FlutterBinaryMessenger
    lazy var store: HKHealthStore = { HKHealthStore() }()
    #if FHK_LOGGER
        fileprivate static var logger: Logger = {
            return Logger(subsystem: Bundle.main.bundleIdentifier!, category: "flutter_health_kit")
        }()
    #endif
    var longRunningQueries: [HKSampleType: HKObserverQueryHandler] = [:]
    var longRunningAnchorQueries: [HKSampleType: HKAnchoredObjectQueryHandler] = [:]

    init(binaryMessenger: FlutterBinaryMessenger) {
        self.binaryMessenger = binaryMessenger
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "flutter_health_kit", binaryMessenger: registrar.messenger())
        let instance = FlutterHealthKitPlugin(binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.addApplicationDelegate(instance)
    }

    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [AnyHashable: Any] = [:]
    ) -> Bool {
        #if FHK_LOGGER
            FlutterHealthKitPlugin.logger.warning("\(#function, privacy: .public)")
        #endif
        if let items = UserDefaults.backgroundDeliveryItems {
            #if FHK_LOGGER
                FlutterHealthKitPlugin.logger.warning(
                    "\(#function, privacy: .public) BackgroundDeliveryItems \(items, privacy: .public)"
                )
            #endif
            Task.init {
                try? await restoreQueries(items: items)
            }
        }

        return true
    }

    private func restoreQueries(items: Set<HKSampleType>) async throws {
        let read = UserDefaults.authorizationReadItems
        #if FHK_LOGGER
            FlutterHealthKitPlugin.logger.warning(
                "\(#function, privacy: .public) \(read, privacy: .public)")
        #endif
        try await store.requestAuthorization(toShare: Set(), read: read)
        try await store.disableAllBackgroundDelivery()
        for item in items {
            let handler = HKObserverQueryHandler(store: store, sampleType: item)
            longRunningQueries[item] = handler
            handler.start()
            try? await store.enableBackgroundDelivery(for: item, frequency: .immediate)
        }
    }
    private func restoreAnchoredQueries(
        items: [HKSampleType: HKQueryAnchor], predicates: [HKSampleType: NSPredicate]
    ) async throws {
        let read = UserDefaults.authorizationReadItemsAnchor
        #if FHK_LOGGER
            FlutterHealthKitPlugin.logger.warning(
                "\(#function, privacy: .public) \(read, privacy: .public)")
        #endif
        try await store.requestAuthorization(toShare: Set(), read: read)
        for (sampleType, anchor) in items {
            let handler = HKAnchoredObjectQueryHandler(
                store: store, sampleType: sampleType, predicate: predicates[sampleType],
                anchor: anchor)
            longRunningAnchorQueries[sampleType] = handler
            handler.start()
        }
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "requestAuthorization":
            guard let arguments = call.arguments as? [String: Any] else {
                result(
                    FlutterError(
                        code: "flutter_health_kit",
                        message:
                            "\(call.method) invalid arguments \(String(describing: call.arguments))",
                        details: nil))
                return
            }
            #if FHK_LOGGER
                FlutterHealthKitPlugin.logger.warning(
                    "\(#function, privacy: .public) -> \(call.method, privacy: .public) : \(arguments, privacy: .public)"
                )
            #endif
            let toShare = (arguments["toShare"] as? [String])?.map { $0.sampleType }.compactMap {
                $0
            }
            let read = (arguments["read"] as? [String])?.map { $0.objectType }.compactMap { $0 }
            store.requestAuthorization(toShare: toShare?.toSet, read: read?.toSet) { value, error in
                if let error = error {
                    result(
                        FlutterError(
                            code: "flutter_health_kit", message: error.localizedDescription,
                            details: nil))
                } else {
                    result(value)
                }
            }
        case "authorizationStatus":
            guard let arguments = call.arguments as? [String] else {
                result(
                    FlutterError(
                        code: "flutter_health_kit",
                        message:
                            "\(call.method) invalid arguments \(String(describing: call.arguments))",
                        details: nil))
                return
            }
            let types = arguments.map { $0.objectType }.compactMap { $0 }
            var data: [String: Int] = [:]
            for type in types {
                data[type.identifier] = store.authorizationStatus(for: type).rawValue
            }
            result(data)
        case "querySampleType":
            guard let arguments = call.arguments as? [String: Any] else {
                result(
                    FlutterError(
                        code: "flutter_health_kit",
                        message:
                            "\(call.method) invalid arguments \(String(describing: call.arguments))",
                        details: nil))
                return
            }
            #if FHK_LOGGER
                FlutterHealthKitPlugin.logger.warning(
                    "\(#function, privacy: .public) -> \(call.method, privacy: .public) : \(arguments, privacy: .public)"
                )
            #endif
            guard let type = arguments["sampleType"] as? String, let sampleType = type.sampleType
            else {
                result(
                    FlutterError(
                        code: "flutter_health_kit",
                        message:
                            "\(call.method) invalid arguments \(String(describing: call.arguments))",
                        details: nil))
                return
            }
            let limit = arguments["limit"] as? Int ?? HKObjectQueryNoLimit
            let sortDescriptors = (arguments["sortDescriptors"] as? [Any])?.map {
                $0 as! [String: Any]
            }
            .map { v in
                NSSortDescriptor(
                    key: v["key"] as? String,
                    ascending: v["ascending"] as! Bool
                )
            }
            let predicate = arguments["predicate"] as? [String: Any]
            preparePredicate(predicate: predicate) { (predicate, error) in
                let query = HKSampleQuery(
                    sampleType: sampleType, predicate: predicate, limit: limit,
                    sortDescriptors: sortDescriptors
                ) { (_, data, error) in
                    guard
                        error == nil,
                        let results = data
                    else {
                        DispatchQueue.main.async {
                            result(
                                FlutterError(
                                    code: "flutter_health_kit",
                                    message: error?.localizedDescription, details: nil))
                        }
                        return
                    }
                    let correlations = results.map({ $0 as? HKCorrelation }).compactMap({ $0 })
                    if !correlations.isEmpty {
                        let types = Set(
                            correlations.map { $0.objects.map { $0.sampleType } }.flatMap { $0 }
                                .compactMap { $0 as? HKQuantityType })
                        self.store.preferredUnits(for: types) { types, error in
                            if let error = error {
                                DispatchQueue.main.async {
                                    result(
                                        FlutterError(
                                            code: "flutter_health_kit",
                                            message: error.localizedDescription, details: error))
                                }
                                return
                            }
                            DispatchQueue.main.async {
                                result(correlations.map { $0.toJson(types) })
                            }
                        }
                        return
                    }
                    let workouts = results.map({ $0 as? HKWorkout }).compactMap({ $0 })
                    if !workouts.isEmpty {
                        DispatchQueue.main.async {
                            result(workouts.map { $0.toJson })
                        }
                        return
                    }
                    let cardiograms = results.map({ $0 as? HKElectrocardiogram }).compactMap({ $0 })
                    if !cardiograms.isEmpty {
                        DispatchQueue.main.async {
                            result(cardiograms.map { $0.toJson })
                        }
                        return
                    }
                    let categories = results.map({ $0 as? HKCategorySample }).compactMap({ $0 })
                    if !categories.isEmpty {
                        DispatchQueue.main.async {
                            result(categories.map { $0.toJson })
                        }
                        return
                    }
                    let quantities = results.map({ $0 as? HKQuantitySample }).compactMap({ $0 })
                    if !quantities.isEmpty {
                        let unitTypes = [sampleType].map({ $0 as? HKQuantityType }).compactMap({
                            $0
                        })
                        self.store.preferredUnits(for: Set(unitTypes)) { types, error in
                            if let error = error {
                                DispatchQueue.main.async {
                                    result(
                                        FlutterError(
                                            code: "flutter_health_kit",
                                            message: error.localizedDescription, details: error))
                                }
                                return
                            }
                            DispatchQueue.main.async {
                                result(quantities.map { $0.toJson(types) })
                            }
                        }
                        return
                    }
                    DispatchQueue.main.async {
                        result([])
                    }
                }
                self.store.execute(query)
            }
        case "queryElectrocardiogram":
            guard let raw = call.arguments as? String, let uuid = UUID(uuidString: raw) else {
                result(
                    FlutterError(
                        code: "flutter_health_kit",
                        message:
                            "\(call.method) invalid arguments \(String(describing: call.arguments))",
                        details: nil))
                return
            }
            let query0 = HKSampleQuery(
                sampleType: HKObjectType.electrocardiogramType(),
                predicate: HKQuery.predicateForObject(with: uuid), limit: 1, sortDescriptors: nil
            ) { _, data0, error0 in
                guard
                    error0 == nil,
                    let ecgSample = data0?.first as? HKElectrocardiogram
                else {
                    DispatchQueue.main.async {
                        result(
                            FlutterError(
                                code: "flutter_health_kit", message: error0?.localizedDescription,
                                details: nil))
                    }
                    return
                }
                var items: [(TimeInterval, HKQuantity)] = []
                let query1 = HKElectrocardiogramQuery(ecgSample) { _, value in
                    switch value {
                    case .measurement(let measurement):
                        if let voltageQuantity = measurement.quantity(
                            for: .appleWatchSimilarToLeadI)
                        {
                            items.append((measurement.timeSinceSampleStart, voltageQuantity))
                        }

                    case .done:
                        DispatchQueue.main.async {
                            result(
                                items.map { (time, quantity) in
                                    return [
                                        "timeSinceSampleStart": time, "values": quantity.toJson,
                                    ]
                                })
                        }
                        return

                    case .error(let error):
                        DispatchQueue.main.async {
                            result(
                                FlutterError(
                                    code: "flutter_health_kit", message: error.localizedDescription,
                                    details: nil))
                        }
                        return

                    @unknown default:
                        DispatchQueue.main.async {
                            result(
                                items.map { (time, quantity) in
                                    return [
                                        "timeSinceSampleStart": time, "values": quantity.toJson,
                                    ]
                                })
                        }
                    }
                }
                self.store.execute(query1)

            }
            store.execute(query0)
        case "queryStatistics":
            guard let arguments = call.arguments as? [String: Any] else {
                result(
                    FlutterError(
                        code: "flutter_health_kit",
                        message:
                            "\(call.method) invalid arguments \(String(describing: call.arguments))",
                        details: nil))
                return
            }
            #if FHK_LOGGER
                FlutterHealthKitPlugin.logger.warning(
                    "\(#function, privacy: .public) -> \(call.method, privacy: .public) : \(arguments, privacy: .public)"
                )
            #endif
            guard let type = arguments["quantityType"] as? String,
                let sampleType = type.quantityTypeIdentifier
            else {
                result(
                    FlutterError(
                        code: "flutter_health_kit",
                        message:
                            "\(call.method) invalid arguments \(String(describing: call.arguments))",
                        details: nil))
                return
            }
            let options: [Int] = arguments["options"] as? [Int] ?? []

            var statisticsOptions: HKStatisticsOptions = []
            for option in options {
                statisticsOptions.insert(HKStatisticsOptions(rawValue: UInt(option)))
            }
            let predicate = arguments["predicate"] as? [String: Any]
            let query = HKStatisticsQuery(
                quantityType: HKQuantityType(sampleType),
                quantitySamplePredicate: predicate?.predicate,
                options: statisticsOptions
            ) { (_, data, error) in
                guard
                    error == nil,
                    let results = data
                else {
                    DispatchQueue.main.async {
                        result(
                            FlutterError(
                                code: "flutter_health_kit", message: error?.localizedDescription,
                                details: nil))
                    }
                    return
                }
                DispatchQueue.main.async {
                    result([])
                }
            }
            store.execute(query)
        case "enableBackgroundDelivery":
            guard let arguments = call.arguments as? [String: Any] else {
                result(
                    FlutterError(
                        code: "flutter_health_kit",
                        message:
                            "\(call.method) invalid arguments \(String(describing: call.arguments))",
                        details: nil))
                return
            }
            #if FHK_LOGGER
                FlutterHealthKitPlugin.logger.warning(
                    "\(#function, privacy: .public) -> \(call.method, privacy: .public) : \(arguments, privacy: .public)"
                )
            #endif
            guard let type = arguments["type"] as? String, let objectType = type.objectType else {
                result(
                    FlutterError(
                        code: "flutter_health_kit",
                        message:
                            "\(call.method) invalid arguments \(String(describing: call.arguments))",
                        details: nil))
                return
            }

            let settings = UserDefaults.standard
            var items: [String] =
                settings.value(forKey: "BackgroundDeliveryItems") as? [String] ?? []
            if !items.contains(type) {
                items.append(type)
                settings.setValue(items, forKey: "BackgroundDeliveryItems")
                settings.synchronize()
            }

            let frequency = arguments["frequency"] as? Int ?? 1
            store.enableBackgroundDelivery(
                for: objectType,
                frequency: HKUpdateFrequency(rawValue: frequency) ?? HKUpdateFrequency.hourly
            ) { value, error in
                if let error = error {
                    result(
                        FlutterError(
                            code: "flutter_health_kit", message: error.localizedDescription,
                            details: nil))
                } else {
                    result(value)
                }
            }
        case "observeQuery":
            guard let arguments = call.arguments as? String, let sampleType = arguments.sampleType
            else {
                result(
                    FlutterError(
                        code: "flutter_health_kit",
                        message:
                            "\(call.method) invalid arguments \(String(describing: call.arguments))",
                        details: nil))
                return
            }
            #if FHK_LOGGER
                FlutterHealthKitPlugin.logger.warning(
                    "\(#function, privacy: .public) -> \(call.method, privacy: .public) : \(arguments, privacy: .public)"
                )
            #endif
            let handler =
                longRunningQueries[sampleType]
                ?? HKObserverQueryHandler(store: store, sampleType: sampleType)

            longRunningQueries[sampleType] = handler
            result("flutter_health_kit_query_\(sampleType.identifier)")
            FlutterEventChannel(
                name: "flutter_health_kit_query_\(sampleType.identifier)",
                binaryMessenger: binaryMessenger
            ).setStreamHandler(handler)

        case "anchoredObjectQuery":
            guard let arguments = call.arguments as? [String: Any] else {
                result(
                    FlutterError(
                        code: "flutter_health_kit",
                        message:
                            "\(call.method) invalid arguments \(String(describing: call.arguments))",
                        details: nil))
                return
            }
            #if FHK_LOGGER
                FlutterHealthKitPlugin.logger.warning(
                    "\(#function, privacy: .public) -> \(call.method, privacy: .public) : \(arguments, privacy: .public)"
                )
            #endif

            guard let type = arguments["sampleType"] as? String, let sampleType = type.sampleType
            else {
                result(
                    FlutterError(
                        code: "flutter_health_kit",
                        message:
                            "\(call.method) invalid arguments \(String(describing: call.arguments))",
                        details: nil))
                return
            }
            let settings = UserDefaults.standard
            var savedPredicates = settings.dictionary(forKey: "BackgroundQueryPredicates") ?? [:]

            let predicateDict = arguments["predicate"] as? [String: Any]
            let predicate = predicateDict?.predicate
            var expectedPredicate: NSPredicate? = (savedPredicates[type] as? [String: Any])?
                .predicate

            let handler: HKAnchoredObjectQueryHandler =
                predicate != expectedPredicate
                ? HKAnchoredObjectQueryHandler(
                    store: store, sampleType: sampleType, predicate: predicate, anchor: nil)
                : longRunningAnchorQueries[sampleType]
                    ?? HKAnchoredObjectQueryHandler(
                        store: store, sampleType: sampleType, predicate: predicate, anchor: nil)
            longRunningAnchorQueries[sampleType] = handler

            if predicate != nil {
                savedPredicates[type] = predicateDict!
            } else {
                savedPredicates.removeValue(forKey: type)
            }
            settings.set(savedPredicates, forKey: "BackgroundQueryPredicates")
            settings.synchronize()

            result("flutter_health_kit_anchored_object_query_\(sampleType.identifier)")
            FlutterEventChannel(
                name: "flutter_health_kit_anchored_object_query_\(sampleType.identifier)",
                binaryMessenger: binaryMessenger
            ).setStreamHandler(handler)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func preparePredicate(
        predicate: [String: Any]?, completion: @escaping (NSPredicate?, Error?) -> Void
    ) {
        if predicate == nil {
            completion(nil, nil)
        } else {
            if predicate?.predicateCode == "predicateForObjectsAssociated" {
                guard let uuidString = predicate?["uuid"] as? String,
                    let uuid = UUID(uuidString: uuidString),
                    let sampleTypeString = predicate?["sampleType"] as? String,
                    let sampleType = sampleTypeString.sampleType
                else {
                    completion(nil, nil)
                    return
                }
                let query0 = HKSampleQuery(
                    sampleType: sampleType, predicate: HKQuery.predicateForObject(with: uuid),
                    limit: 1, sortDescriptors: nil
                ) { _, data0, error0 in
                    guard
                        error0 == nil,
                        let ecgSample = data0?.first as? HKElectrocardiogram
                    else {
                        completion(nil, error0 ?? HKError.init(.errorNoData))
                        return
                    }
                    completion(
                        HKQuery.predicateForObjectsAssociated(electrocardiogram: ecgSample), nil)
                }
                store.execute(query0)
            } else {
                completion(predicate?.predicate, nil)
            }
        }
    }
}

class HKObserverQueryHandler: NSObject, FlutterStreamHandler {
    let store: HKHealthStore
    let sampleType: HKSampleType
    var query: HKObserverQuery?
    var eventSink: FlutterEventSink?
    var items: [HKObjectType] = []

    init(store: HKHealthStore, sampleType: HKSampleType) {
        self.store = store
        self.sampleType = sampleType
    }

    var id: String {
        sampleType.identifier
    }

    public func onListen(
        withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        self.eventSink = events
        #if FHK_LOGGER
            FlutterHealthKitPlugin.logger.warning(
                "HKObserverQueryHandler->\(#function, privacy: .public) \(self.items, privacy: .public)"
            )
        #endif
        for item in items {
            events(item.identifier)
        }
        items.removeAll()
        start()
        return nil
    }

    public func start() {
        if query == nil {
            let query = HKObserverQuery(sampleType: sampleType, predicate: nil) {
                query, handler, error in
                #if FHK_LOGGER
                    FlutterHealthKitPlugin.logger.warning(
                        "HKObserverQuery \(query.objectType, privacy: .public)")
                #endif
                if let error = error {
                    #if FHK_LOGGER
                        FlutterHealthKitPlugin.logger.warning(
                            "HKObserverQuery \(error.localizedDescription, privacy: .public)")
                    #endif
                    DispatchQueue.main.async {
                        self.eventSink?(
                            FlutterError(
                                code: "flutter_health_kit", message: error.localizedDescription,
                                details: nil))
                    }
                } else if let objectType = query.objectType {
                    DispatchQueue.main.async {
                        if let sink = self.eventSink {
                            if !self.items.isEmpty {
                                for item in self.items {
                                    sink(item.identifier)
                                }
                                self.items.removeAll()
                            }
                            sink(objectType.identifier)
                        } else {
                            self.items.append(objectType)
                        }
                        #if FHK_LOGGER
                            FlutterHealthKitPlugin.logger.warning(
                                "HKObserverQuery queued \(self.items, privacy: .public)")
                        #endif
                    }
                }
                handler()
            }

            store.execute(query)
            self.query = query
        }
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        #if FHK_LOGGER
            FlutterHealthKitPlugin.logger.warning(
                "HKObserverQueryHandler->\(#function, privacy: .public) \(self.items, privacy: .public)"
            )
        #endif
        if let query = self.query {
            store.stop(query)
            self.query = nil
        }
        eventSink = nil
        items.removeAll()
        return nil
    }

}

class HKAnchoredObjectQueryHandler: NSObject, FlutterStreamHandler {
    let store: HKHealthStore
    let sampleType: HKSampleType
    let predicate: NSPredicate?
    let anchor: HKQueryAnchor?
    var query: HKAnchoredObjectQuery?
    var eventSink: FlutterEventSink?
    var items: [[String: Any]] = []

    init(
        store: HKHealthStore, sampleType: HKSampleType, predicate: NSPredicate?,
        anchor: HKQueryAnchor?
    ) {
        self.store = store
        self.sampleType = sampleType
        self.predicate = predicate
        self.anchor = anchor
    }

    var id: String {
        sampleType.identifier
    }

    public func onListen(
        withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        self.eventSink = events
        #if FHK_LOGGER
            FlutterHealthKitPlugin.logger.warning(
                "HKAnchoredObjectQueryHandler->\(#function, privacy: .public) \(self.items, privacy: .public)"
            )
        #endif
        for item in items {
            events(item)
        }
        items.removeAll()
        start()
        return nil
    }

    public func start() {
        if query == nil {
            let handler:
                (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) ->
                    Void = { query, samples, deletedObjects, newAnchor, error in
                        #if FHK_LOGGER
                            FlutterHealthKitPlugin.logger.warning(
                                "HKAnchoredObjectQuery \(query.objectType, privacy: .public)")
                        #endif
                        if let error = error {
                            #if FHK_LOGGER
                                FlutterHealthKitPlugin.logger.warning(
                                    "HKAnchoredObjectQuery \(error.localizedDescription, privacy: .public)"
                                )
                            #endif
                            DispatchQueue.main.async {
                                self.eventSink?(
                                    FlutterError(
                                        code: "flutter_health_kit",
                                        message: error.localizedDescription, details: nil))
                            }
                        } else {
                            let settings = UserDefaults.standard
                            var items = settings.dictionary(forKey: "BackgroundQueryAnchors") ?? [:]
                            if let anchorData = try? NSKeyedArchiver.archivedData(
                                withRootObject: newAnchor, requiringSecureCoding: true)
                            {
                                items[self.sampleType.identifier] = anchorData
                                settings.set(items, forKey: "BackgroundQueryAnchors")
                                settings.synchronize()
                            }

                            let correlations = (samples ?? []).map({ $0 as? HKCorrelation })
                                .compactMap({ $0 })
                            if !correlations.isEmpty {
                                let types = Set(
                                    correlations.map { $0.objects.map { $0.sampleType } }.flatMap {
                                        $0
                                    }.compactMap { $0 as? HKQuantityType })
                                self.store.preferredUnits(for: types) { types, error in
                                    if let error = error {
                                        DispatchQueue.main.async {
                                            self.eventSink?(
                                                FlutterError(
                                                    code: "flutter_health_kit",
                                                    message: error.localizedDescription,
                                                    details: error))
                                        }
                                        return
                                    }
                                    let jsonDictionary: [String: Any] = [
                                        "samples": correlations.map { $0.toJson(types) },
                                        "deletedObjects": (deletedObjects ?? []).map({
                                            $0.uuid.uuidString
                                        }),
                                    ].compactMapValues({ $0 })
                                    DispatchQueue.main.async {
                                        if let sink = self.eventSink {
                                            if !self.items.isEmpty {
                                                for item in self.items {
                                                    sink(item)
                                                }
                                                self.items.removeAll()
                                            }
                                            sink(jsonDictionary)
                                        } else {
                                            self.items.append(jsonDictionary)
                                        }
                                        #if FHK_LOGGER
                                            FlutterHealthKitPlugin.logger.warning(
                                                "HKAnchoredObjectQuery queued \(self.items, privacy: .public)"
                                            )
                                        #endif
                                    }
                                }
                                return
                            }
                            let workouts = (samples ?? []).map({ $0 as? HKWorkout }).compactMap({
                                $0
                            })
                            if !workouts.isEmpty {
                                let unitTypes = Set(
                                    workouts.map { $0.allStatistics.keys }.flatMap { $0 })
                                self.store.preferredUnits(for: unitTypes) { types, error in
                                    if let error = error {
                                        DispatchQueue.main.async {
                                            self.eventSink?(
                                                FlutterError(
                                                    code: "flutter_health_kit",
                                                    message: error.localizedDescription,
                                                    details: nil))
                                        }
                                        return
                                    }
                                    let jsonDictionary: [String: Any] = [
                                        "samples": workouts.map { $0.toJson(types) },
                                        "deletedObjects": (deletedObjects ?? []).map({
                                            $0.uuid.uuidString
                                        }),
                                    ].compactMapValues({ $0 })
                                    DispatchQueue.main.async {
                                        if let sink = self.eventSink {
                                            if !self.items.isEmpty {
                                                for item in self.items {
                                                    sink(item)
                                                }
                                                self.items.removeAll()
                                            }
                                            sink(jsonDictionary)
                                        } else {
                                            self.items.append(jsonDictionary)
                                        }
                                        #if FHK_LOGGER
                                            FlutterHealthKitPlugin.logger.warning(
                                                "HKAnchoredObjectQuery queued \(self.items, privacy: .public)"
                                            )
                                        #endif
                                    }
                                }
                                return
                            }
                            let ecgs = (samples ?? []).map({ $0 as? HKElectrocardiogram })
                                .compactMap({ $0 })
                            if !ecgs.isEmpty {
                                Task {
                                    let voltageUnit = HKUnit.voltUnit(with: .milli)
                                    var ecgDicts: [Any] = []
                                    for ecg in ecgs {
                                        var voltageMeasurementsLeadI: [Any] = []
                                        let ecgDescriptor = HKElectrocardiogramQueryDescriptor(ecg)
                                        let voltages = ecgDescriptor.results(for: self.store)
                                        do {
                                            for try await measurement in voltages {
                                                if let voltageQuantity = measurement.quantity(
                                                    for: .appleWatchSimilarToLeadI)
                                                {
                                                    voltageMeasurementsLeadI.append(
                                                        voltageQuantity.doubleValue(
                                                            for: voltageUnit))
                                                }
                                            }
                                        } catch {
                                            DispatchQueue.main.async {
                                                self.eventSink?(
                                                    FlutterError(
                                                        code: "flutter_health_kit",
                                                        message: error.localizedDescription,
                                                        details: nil))
                                            }
                                            return
                                        }
                                        ecgDicts.append(
                                            ecg.toJson([
                                                [
                                                    "lead": "I",
                                                    "values": voltageMeasurementsLeadI,
                                                    "unit": voltageUnit.unitString,
                                                ]
                                            ]))
                                    }
                                    let jsonDictionary: [String: Any] = [
                                        "samples": ecgDicts,
                                        "deletedObjects": (deletedObjects ?? []).map({
                                            $0.uuid.uuidString
                                        }),
                                    ].compactMapValues({ $0 })
                                    DispatchQueue.main.async {
                                        if let sink = self.eventSink {
                                            if !self.items.isEmpty {
                                                for item in self.items {
                                                    sink(item)
                                                }
                                                self.items.removeAll()
                                            }
                                            sink(jsonDictionary)
                                        } else {
                                            self.items.append(jsonDictionary)
                                        }
                                        #if FHK_LOGGER
                                            FlutterHealthKitPlugin.logger.warning(
                                                "HKAnchoredObjectQuery queued \(self.items, privacy: .public)"
                                            )
                                        #endif
                                    }
                                }
                                return
                            }
                            let quantities = (samples ?? []).map({ $0 as? HKQuantitySample })
                                .compactMap({ $0 })
                            if !quantities.isEmpty {
                                let unitTypes = [self.sampleType].map({ $0 as? HKQuantityType })
                                    .compactMap({ $0 })
                                self.store.preferredUnits(for: Set(unitTypes)) { types, error in
                                    if let error = error {
                                        DispatchQueue.main.async {
                                            self.eventSink?(
                                                FlutterError(
                                                    code: "flutter_health_kit",
                                                    message: error.localizedDescription,
                                                    details: nil))
                                        }
                                        return
                                    }
                                    let jsonDictionary: [String: Any] = [
                                        "samples": quantities.map { $0.toJson(types) },
                                        "deletedObjects": (deletedObjects ?? []).map({
                                            $0.uuid.uuidString
                                        }),
                                    ].compactMapValues({ $0 })
                                    DispatchQueue.main.async {
                                        if let sink = self.eventSink {
                                            if !self.items.isEmpty {
                                                for item in self.items {
                                                    sink(item)
                                                }
                                                self.items.removeAll()
                                            }
                                            sink(jsonDictionary)
                                        } else {
                                            self.items.append(jsonDictionary)
                                        }
                                        #if FHK_LOGGER
                                            FlutterHealthKitPlugin.logger.warning(
                                                "HKAnchoredObjectQuery queued \(self.items, privacy: .public)"
                                            )
                                        #endif
                                    }
                                }
                                return
                            }
                            let categories = (samples ?? []).map({ $0 as? HKCategorySample })
                                .compactMap({ $0 })
                            if !categories.isEmpty {
                                let jsonDictionary: [String: Any] = [
                                    "samples": categories.map { $0.toJson },
                                    "deletedObjects": (deletedObjects ?? []).map({
                                        $0.uuid.uuidString
                                    }),
                                ].compactMapValues({ $0 })
                                DispatchQueue.main.async {
                                    if let sink = self.eventSink {
                                        if !self.items.isEmpty {
                                            for item in self.items {
                                                sink(item)
                                            }
                                            self.items.removeAll()
                                        }
                                        sink(jsonDictionary)
                                    } else {
                                        self.items.append(jsonDictionary)
                                    }
                                    #if FHK_LOGGER
                                        FlutterHealthKitPlugin.logger.warning(
                                            "HKAnchoredObjectQuery queued \(self.items, privacy: .public)"
                                        )
                                    #endif
                                }
                                return
                            }

                            let deletedObjectsArray: [String] = (deletedObjects ?? []).map({
                                $0.uuid.uuidString
                            })
                            if !deletedObjectsArray.isEmpty {
                                let jsonDictionary: [String: Any] = [
                                    "deletedObjects": deletedObjectsArray
                                ]
                                DispatchQueue.main.async {
                                    if let sink = self.eventSink {
                                        if !self.items.isEmpty {
                                            for item in self.items {
                                                sink(item)
                                            }
                                            self.items.removeAll()
                                        }
                                        sink(jsonDictionary)
                                    } else {
                                        self.items.append(jsonDictionary)
                                    }
                                    #if FHK_LOGGER
                                        FlutterHealthKitPlugin.logger.warning(
                                            "HKAnchoredObjectQuery queued \(self.items, privacy: .public)"
                                        )
                                    #endif
                                }
                                return
                            }
                        }
                    }
            let query = HKAnchoredObjectQuery(
                type: sampleType,
                predicate: predicate,
                anchor: anchor,
                limit: HKObjectQueryNoLimit,
                resultsHandler: handler)
            query.updateHandler = handler
            store.execute(query)
            self.query = query
        }
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        #if FHK_LOGGER
            FlutterHealthKitPlugin.logger.warning(
                "HKAnchoredObjectQueryHandler->\(#function, privacy: .public) \(self.items, privacy: .public)"
            )
        #endif
        if let query = self.query {
            store.stop(query)
            self.query = nil
        }
        eventSink = nil
        items.removeAll()
        return nil
    }

}

extension UserDefaults {
    class var backgroundDeliveryItems: Set<HKSampleType>? {
        let settings = UserDefaults.standard
        if let items = settings.value(forKey: "BackgroundDeliveryItems") as? [String] {
            let values = items.map { $0.sampleType }.compactMap { $0 }.toSet
            if values.isEmpty {
                return nil
            }
            return values
        }

        return nil
    }

    class var backgroundQueryAnchors: [HKSampleType: HKQueryAnchor]? {
        let settings = UserDefaults.standard
        if let items = settings.dictionary(forKey: "BackgroundQueryAnchors") {
            let kvlist = items.compactMap { (key, value) in
                if let sample = key.sampleType, let data = value as? Data,
                    let anchor = try? NSKeyedUnarchiver.unarchivedObject(
                        ofClass: HKQueryAnchor.self, from: data)
                {
                    return (sample, anchor)
                } else {
                    return nil
                }
            }
            let values = Dictionary(uniqueKeysWithValues: kvlist)
            if values.isEmpty {
                return nil
            }
            return values
        }

        return nil
    }

    class var backgroundQueryPredicates: [HKSampleType: NSPredicate]? {
        let settings = UserDefaults.standard
        if let items = settings.dictionary(forKey: "BackgroundQueryPredicates") {
            let kvlist = items.compactMap { (key, value) in
                if let sample = key.sampleType, let predicate = (value as? [String: Any])?.predicate
                {
                    return (sample, predicate)
                } else {
                    return nil
                }
            }
            let values = Dictionary(uniqueKeysWithValues: kvlist)
            if values.isEmpty {
                return nil
            }
            return values
        }

        return nil
    }

    class var authorizationReadItemsAnchor: Set<HKSampleType> {
        if let items = UserDefaults.backgroundQueryAnchors {
            var values = Set<HKSampleType?>()
            for item in items.keys {
                if item is HKCorrelationType {
                    if item.identifier == HKCorrelationTypeIdentifier.bloodPressure.rawValue {
                        values.insert(
                            HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue.sampleType)
                        values.insert(
                            HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue.sampleType)
                    }
                } else {
                    values.insert(item)
                }
            }
            return values.compactMap { $0 }.toSet
        }

        return Set()
    }
    class var authorizationReadItems: Set<HKSampleType> {
        if let items = UserDefaults.backgroundDeliveryItems {
            var values = Set<HKSampleType?>()
            for item in items {
                if item is HKCorrelationType {
                    if item.identifier == HKCorrelationTypeIdentifier.bloodPressure.rawValue {
                        values.insert(
                            HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue.sampleType)
                        values.insert(
                            HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue.sampleType)
                    }
                } else {
                    values.insert(item)
                }
            }
            return values.compactMap { $0 }.toSet
        }

        return Set()
    }
}
