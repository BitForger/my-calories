//
//  ContentView.swift
//  my-calories
//
//  Created by Noah on 8/27/26.
//

import SwiftUI
import SwiftData
import Combine
import UserNotifications
#if canImport(HealthKit)
import HealthKit
#endif

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FoodEntry.consumedAt, order: .reverse) private var entries: [FoodEntry]
    @Query(sort: \FoodCatalogItem.name) private var foodCatalog: [FoodCatalogItem]
    @Query private var profiles: [UserProfile]

    @State private var showingAddEntrySheet = false
    @StateObject private var syncCoordinator = HealthKitSyncCoordinator()
    private let reminderManager = ReminderManager()

    @AppStorage("hasCompletedQuickStart") private var hasCompletedQuickStart = false
    @AppStorage("useCloudKitSync") private var useCloudKitSync = true
    @AppStorage("enableReminders") private var enableReminders = false

    var body: some View {
        Group {
            if hasCompletedQuickStart {
                NavigationViewWrapper {
                    List {
                        Section("Today") {
                            dailyCard
                        }

                        Section("Week") {
                            weeklyCard
                        }

                        Section("Consistency") {
                            consistencyCard
                        }

                        Section("Targets") {
                            targetModePicker
                            metabolismCard
                        }

                        if !syncCoordinator.syncMessage.isEmpty {
                            Section("Sync") {
                                Text(syncCoordinator.syncMessage)
                                    .font(.footnote)
                            }
                        }

                        Section("Recent Entries") {
                            if entries.isEmpty {
                                Text("No entries yet. Tap + to add your first meal.")
                                    .foregroundStyle(.secondary)
                            }

                            ForEach(entries.prefix(20)) { entry in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(entry.foodName)
                                        Text(entry.amountDescription)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing) {
                                        Text("\(Int(entry.calories)) cal")
                                        Text(entry.consumedAt, format: .dateTime.hour().minute())
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .onDelete(perform: deleteEntries)
                        }
                    }
                    .toolbar {
#if os(iOS)
                        ToolbarItem(placement: .topBarTrailing) {
                            EditButton()
                        }
#endif
                        ToolbarItem {
                            Button(action: { showingAddEntrySheet = true }) {
                                Label("Add Entry", systemImage: "plus")
                            }
                        }
                    }
                    .sheet(isPresented: $showingAddEntrySheet) {
                        AddFoodEntrySheet(foodCatalog: foodCatalog) { payload in
                            addEntry(payload)
                        }
                    }
                    .task {
                        bootstrapIfNeeded()
                        await refreshFromHealthKit()
                    }
                }
            } else {
                QuickStartOnboardingView(
                    useCloudKitSync: $useCloudKitSync,
                    enableReminders: $enableReminders,
                    onRequestHealthKit: {
                        await syncCoordinator.requestAuthorization()
                    },
                    onComplete: {
                        hasCompletedQuickStart = true
                    }
                )
                .task {
                    bootstrapIfNeeded()
                }
            }
        }
#if os(macOS)
        .navigationSplitViewColumnWidth(min: 320, ideal: 360)
#endif
        .onChange(of: enableReminders) { _, enabled in
            Task {
                await updateReminderSchedule(enabled: enabled)
            }
        }
    }

    private var activeProfile: UserProfile {
        if let existing = profiles.first {
            return existing
        }

        let profile = UserProfile()
        modelContext.insert(profile)
        return profile
    }

    private var selectedTargetMode: TargetMode {
        activeProfile.selectedTargetMode
    }

    private var todayCalories: Double {
        CalorieSummaryCalculator.dailyTotal(from: entries, on: .now)
    }

    private var weeklyCalories: Double {
        CalorieSummaryCalculator.weeklyTotal(from: entries, around: .now)
    }

    private var dailyTarget: Double {
        selectedTargetMode == .dynamic ? activeProfile.estimatedTDEE() : activeProfile.dailyCalorieTarget
    }

    private var weeklyTarget: Double {
        if selectedTargetMode == .dynamic {
            return activeProfile.estimatedTDEE() * 7
        }
        return activeProfile.weeklyCalorieTarget
    }

    private var weekLoggedDays: Int {
        StreakCalculator.weekLoggedDays(entries: entries, around: .now)
    }

    private var currentStreakDays: Int {
        StreakCalculator.currentDailyLoggingStreak(entries: entries)
    }

    private var dailyCard: some View {
        let progress = max(0, min(1, todayCalories / max(dailyTarget, 1)))
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(Int(todayCalories)) / \(Int(dailyTarget)) cal")
                .font(.title3.weight(.semibold))
            ProgressView(value: progress)
                .tint(.green)
            Text("Daily progress")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var weeklyCard: some View {
        let status = CalorieSummaryCalculator.weeklyStatus(total: weeklyCalories, target: weeklyTarget)
        let progress = max(0, min(1, weeklyCalories / max(weeklyTarget, 1)))
        let weekRange = CalorieSummaryCalculator.weekRange(for: .now)
        let remaining = CalorieSummaryCalculator.remainingWeeklyCalories(total: weeklyCalories, target: weeklyTarget)

        return VStack(alignment: .leading, spacing: 8) {
            Text("\(Int(weeklyCalories)) / \(Int(weeklyTarget)) cal")
                .font(.title3.weight(.semibold))
            ProgressView(value: progress)
                .tint(.blue)
            Text("Week \(weekRange.start, format: .dateTime.month().day()) - \(weekRange.end.addingTimeInterval(-1), format: .dateTime.month().day())")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(weeklyStatusText(status))
                .font(.caption.weight(.semibold))
                .foregroundStyle(weeklyStatusColor(status))
            Text("Remaining this week: \(Int(remaining)) cal")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var consistencyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current streak: \(currentStreakDays) day\(currentStreakDays == 1 ? "" : "s")")
            Text("Logged this week: \(weekLoggedDays) of 7 days")
            Text("Weekly adherence matters as much as daily precision.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var targetModePicker: some View {
        Picker("Target Mode", selection: Binding(get: { selectedTargetMode }, set: { activeProfile.selectedTargetMode = $0 })) {
            ForEach(TargetMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private var metabolismCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Estimated BMR: \(Int(activeProfile.estimatedBMR())) cal/day")
            Text("Estimated TDEE: \(Int(activeProfile.estimatedTDEE())) cal/day")
            Text("Dynamic mode uses TDEE to drive daily and weekly targets.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func weeklyStatusText(_ status: WeeklyAggregateStatus) -> String {
        switch status {
        case .onTrack:
            return "On track this week"
        case .aboveTarget:
            return "Above weekly target"
        case .belowTarget:
            return "Below weekly target"
        }
    }

    private func weeklyStatusColor(_ status: WeeklyAggregateStatus) -> Color {
        switch status {
        case .onTrack:
            return .green
        case .aboveTarget:
            return .orange
        case .belowTarget:
            return .red
        }
    }

    private func addEntry(_ payload: AddFoodEntryPayload) {
        withAnimation {
            let entry = FoodEntry(
                foodName: payload.foodName,
                amountDescription: payload.amountDescription,
                calories: payload.calories,
                consumedAt: payload.consumedAt,
                updatedAt: .now,
                source: "manual"
            )
            modelContext.insert(entry)
        }

        Task {
            await syncAllEntriesWithHealthKit()
        }
    }

    private func deleteEntries(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(entries[index])
            }
        }

        Task {
            await syncAllEntriesWithHealthKit()
        }
    }

    private func bootstrapIfNeeded() {
        if profiles.isEmpty {
            modelContext.insert(UserProfile())
        }

        if foodCatalog.isEmpty {
            FoodCatalogSeed.defaults.forEach {
                modelContext.insert(
                    FoodCatalogItem(
                        name: $0.name,
                        defaultAmountDescription: $0.amount,
                        caloriesPerDefaultAmount: $0.calories
                    )
                )
            }
        }

        Task {
            await updateReminderSchedule(enabled: enableReminders)
        }
    }

    private func refreshFromHealthKit() async {
        guard hasCompletedQuickStart else { return }
        let startDate = Calendar.gregorianSundayStart.date(byAdding: .day, value: -14, to: .now) ?? .now
        let payloads = await syncCoordinator.pullLatestEntries(from: startDate, to: .now)

        guard !payloads.isEmpty else { return }

        for payload in payloads {
            if let match = entries.first(where: { $0.healthKitSampleIdentifier == payload.healthKitSampleIdentifier }) {
                if payload.updatedAt > match.updatedAt {
                    match.foodName = payload.foodName
                    match.amountDescription = payload.amountDescription
                    match.calories = payload.calories
                    match.consumedAt = payload.consumedAt
                    match.updatedAt = payload.updatedAt
                    match.source = "healthKit"
                }
            } else {
                modelContext.insert(
                    FoodEntry(
                        id: payload.id,
                        foodName: payload.foodName,
                        amountDescription: payload.amountDescription,
                        calories: payload.calories,
                        consumedAt: payload.consumedAt,
                        updatedAt: payload.updatedAt,
                        source: "healthKit",
                        healthKitSampleIdentifier: payload.healthKitSampleIdentifier
                    )
                )
            }
        }
    }

    private func syncAllEntriesWithHealthKit() async {
        guard hasCompletedQuickStart else { return }
        let snapshots = entries.map(CalorieEntryPayload.init)
        let mergedPayloads = await syncCoordinator.sync(localEntries: snapshots)

        for payload in mergedPayloads {
            if let match = entries.first(where: { $0.id == payload.id || $0.healthKitSampleIdentifier == payload.healthKitSampleIdentifier }) {
                if payload.updatedAt > match.updatedAt || payload.updatedAt == match.updatedAt {
                    match.foodName = payload.foodName
                    match.amountDescription = payload.amountDescription
                    match.calories = payload.calories
                    match.consumedAt = payload.consumedAt
                    match.updatedAt = payload.updatedAt
                    match.healthKitSampleIdentifier = payload.healthKitSampleIdentifier
                    match.source = payload.source
                }
            } else {
                modelContext.insert(
                    FoodEntry(
                        id: payload.id,
                        foodName: payload.foodName,
                        amountDescription: payload.amountDescription,
                        calories: payload.calories,
                        consumedAt: payload.consumedAt,
                        updatedAt: payload.updatedAt,
                        source: payload.source,
                        healthKitSampleIdentifier: payload.healthKitSampleIdentifier
                    )
                )
            }
        }
    }

    private func updateReminderSchedule(enabled: Bool) async {
        do {
            if enabled {
                try await reminderManager.enableDefaultReminder()
            } else {
                await reminderManager.disableReminder()
            }
        } catch {
            syncCoordinator.syncMessage = "Reminder setup failed: \(error.localizedDescription)"
        }
    }

}

fileprivate struct NavigationViewWrapper<Content: View>: View {
    let content: () -> Content

    var body: some View {
#if os(macOS)
        NavigationSplitView {
            content()
        } detail: {
            Text("Select an item")
        }
#else
        content()
#endif
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [FoodEntry.self, FoodCatalogItem.self, UserProfile.self], inMemory: true)
}

private struct AddFoodEntryPayload {
    let foodName: String
    let amountDescription: String
    let calories: Double
    let consumedAt: Date
}

private struct AddFoodEntrySheet: View {
    @Environment(\.dismiss) private var dismiss

    let foodCatalog: [FoodCatalogItem]
    let onSave: (AddFoodEntryPayload) -> Void

    @State private var selectedCatalogID: UUID?
    @State private var foodName = ""
    @State private var amountDescription = ""
    @State private var caloriesText = ""
    @State private var consumedAt = Date()

    var body: some View {
        NavigationStack {
            Form {
                if !foodCatalog.isEmpty {
                    Picker("Quick pick", selection: $selectedCatalogID) {
                        Text("None").tag(UUID?.none)
                        ForEach(foodCatalog) { item in
                            Text(item.name).tag(UUID?.some(item.id))
                        }
                    }
                    .onChange(of: selectedCatalogID) { _, newValue in
                        guard let id = newValue, let item = foodCatalog.first(where: { $0.id == id }) else { return }
                        foodName = item.name
                        amountDescription = item.defaultAmountDescription
                        caloriesText = String(Int(item.caloriesPerDefaultAmount))
                    }
                }

                TextField("Food name", text: $foodName)
                TextField("Amount", text: $amountDescription)
                TextField("Calories", text: $caloriesText)
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif
                DatePicker("Time", selection: $consumedAt)
            }
            .navigationTitle("Manual Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!isFormValid)
                }
            }
        }
    }

    private var isFormValid: Bool {
        !foodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !amountDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && Double(caloriesText) != nil
    }

    private func save() {
        guard let calories = Double(caloriesText) else { return }
        onSave(
            AddFoodEntryPayload(
                foodName: foodName.trimmingCharacters(in: .whitespacesAndNewlines),
                amountDescription: amountDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                calories: calories,
                consumedAt: consumedAt
            )
        )
        dismiss()
    }
}

private struct QuickStartOnboardingView: View {
    @Binding var useCloudKitSync: Bool
    @Binding var enableReminders: Bool

    let onRequestHealthKit: () async -> Void
    let onComplete: () -> Void

    @State private var step = 0

    var body: some View {
        VStack(spacing: 20) {
            Text("Quick Start")
                .font(.largeTitle.bold())

            Text("Step \(step + 1) of 3")
                .font(.headline)
                .foregroundStyle(.secondary)

            Group {
                switch step {
                case 0:
                    stepOnePrivacy
                case 1:
                    stepTwoHealthKit
                default:
                    stepThreePreferences
                }
            }

            HStack {
                Button("Back") {
                    step = max(0, step - 1)
                }
                .disabled(step == 0)

                Spacer()

                Button(step == 2 ? "Finish" : "Next") {
                    if step == 2 {
                        onComplete()
                    } else {
                        step += 1
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
        }
        .padding()
    }

    private var stepOnePrivacy: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Privacy first")
                .font(.title3.weight(.semibold))
            Text("Your entries are stored locally first. You control Health and Cloud sync in Settings at any time.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stepTwoHealthKit: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Health integration")
                .font(.title3.weight(.semibold))
            Text("The app reads latest calorie data from Apple Health before syncing, then writes updates.")
                .foregroundStyle(.secondary)
            Button("Allow Health Access") {
                Task {
                    await onRequestHealthKit()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stepThreePreferences: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sync preferences")
                .font(.title3.weight(.semibold))
            Toggle("Enable CloudKit sync", isOn: $useCloudKitSync)
            Toggle("Enable reminders", isOn: $enableReminders)
            Text("You can change these any time later.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CalorieEntryPayload: Hashable {
    var id: UUID
    var foodName: String
    var amountDescription: String
    var calories: Double
    var consumedAt: Date
    var updatedAt: Date
    var source: String
    var healthKitSampleIdentifier: String?

    init(id: UUID = UUID(), foodName: String, amountDescription: String, calories: Double, consumedAt: Date, updatedAt: Date, source: String, healthKitSampleIdentifier: String? = nil) {
        self.id = id
        self.foodName = foodName
        self.amountDescription = amountDescription
        self.calories = calories
        self.consumedAt = consumedAt
        self.updatedAt = updatedAt
        self.source = source
        self.healthKitSampleIdentifier = healthKitSampleIdentifier
    }

    init(_ entry: FoodEntry) {
        self.init(
            id: entry.id,
            foodName: entry.foodName,
            amountDescription: entry.amountDescription,
            calories: entry.calories,
            consumedAt: entry.consumedAt,
            updatedAt: entry.updatedAt,
            source: entry.source,
            healthKitSampleIdentifier: entry.healthKitSampleIdentifier
        )
    }
}

@MainActor
private final class HealthKitSyncCoordinator: ObservableObject {
    @Published var syncMessage = ""
    private let healthKitService = HealthKitService()

    func requestAuthorization() async {
        do {
            try await healthKitService.requestAuthorization()
            syncMessage = "HealthKit access granted."
        } catch {
            syncMessage = "HealthKit authorization failed: \(error.localizedDescription)"
        }
    }

    func pullLatestEntries(from startDate: Date, to endDate: Date) async -> [CalorieEntryPayload] {
        do {
            return try await healthKitService.fetchEntries(from: startDate, to: endDate)
        } catch {
            syncMessage = "HealthKit pull failed: \(error.localizedDescription)"
            return []
        }
    }

    // Sync rule: fetch latest HealthKit data first, then merge, then push if needed.
    func sync(localEntries: [CalorieEntryPayload]) async -> [CalorieEntryPayload] {
        do {
            let merged = try await healthKitService.syncReadFirst(localEntries: localEntries)
            syncMessage = "Last sync: \(Date.now.formatted(date: .omitted, time: .shortened))"
            return merged
        } catch {
            syncMessage = "HealthKit sync failed: \(error.localizedDescription)"
            return localEntries
        }
    }
}

private actor ReminderManager {
    private let reminderIdentifier = "daily-calorie-log-reminder"

    func enableDefaultReminder() async throws {
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "Log your calories"
        content.body = "A quick log now helps keep your weekly target on track."
        content.sound = .default

        var components = DateComponents()
        components.hour = 20
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: reminderIdentifier, content: content, trigger: trigger)

        center.removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])
        try await center.add(request)
    }

    func disableReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])
    }
}

private final class HealthKitService {
#if canImport(HealthKit)
    private let store = HKHealthStore()
    private let dietaryType = HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!
#endif

    enum ServiceError: LocalizedError {
        case unsupported
        case authorizationUnavailable

        var errorDescription: String? {
            switch self {
            case .unsupported:
                return "HealthKit is not available on this platform."
            case .authorizationUnavailable:
                return "HealthKit permissions are unavailable."
            }
        }
    }

    func requestAuthorization() async throws {
#if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            throw ServiceError.authorizationUnavailable
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: [dietaryType], read: [dietaryType]) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if granted {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.authorizationUnavailable)
                }
            }
        }
#else
        throw ServiceError.unsupported
#endif
    }

    func fetchEntries(from startDate: Date, to endDate: Date) async throws -> [CalorieEntryPayload] {
#if canImport(HealthKit)
        let samples = try await fetchSamples(from: startDate, to: endDate)
        return samples.map { sample in
            let metadata = sample.metadata ?? [:]
            let idString = metadata["localEntryID"] as? String
            let entryID = UUID(uuidString: idString ?? "") ?? UUID()
            let foodName = metadata["foodName"] as? String ?? "Health Entry"
            let amount = metadata["amount"] as? String ?? "Imported"
            let updatedAt = metadata["updatedAt"] as? Date ?? sample.endDate
            return CalorieEntryPayload(
                id: entryID,
                foodName: foodName,
                amountDescription: amount,
                calories: sample.quantity.doubleValue(for: .kilocalorie()),
                consumedAt: sample.startDate,
                updatedAt: updatedAt,
                source: "healthKit",
                healthKitSampleIdentifier: sample.uuid.uuidString
            )
        }
#else
        throw ServiceError.unsupported
#endif
    }

    func syncReadFirst(localEntries: [CalorieEntryPayload]) async throws -> [CalorieEntryPayload] {
#if canImport(HealthKit)
        guard !localEntries.isEmpty else { return [] }

        let startDate = localEntries.map(\.consumedAt).min() ?? Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
        let endDate = Date.now

        // Always pull from HealthKit before attempting to write.
        let remoteEntries = try await fetchEntries(from: startDate, to: endDate)
        let merged = merge(localEntries: localEntries, remoteEntries: remoteEntries)
        let pushCandidates = entriesNeedingPush(localEntries: localEntries, remoteEntries: remoteEntries)
        if !pushCandidates.isEmpty {
            try await saveToHealthKit(pushCandidates)
        }
        return merged
#else
        return localEntries
#endif
    }

#if canImport(HealthKit)
    private func fetchSamples(from startDate: Date, to endDate: Date) async throws -> [HKQuantitySample] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKQuantitySample], Error>) in
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
            let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            let query = HKSampleQuery(sampleType: dietaryType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: sort) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    let values = (samples as? [HKQuantitySample]) ?? []
                    continuation.resume(returning: values)
                }
            }
            store.execute(query)
        }
    }

    private func saveToHealthKit(_ entries: [CalorieEntryPayload]) async throws {
        let samples = entries.map { entry in
            HKQuantitySample(
                type: dietaryType,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: entry.calories),
                start: entry.consumedAt,
                end: entry.consumedAt,
                metadata: [
                    "localEntryID": entry.id.uuidString,
                    "foodName": entry.foodName,
                    "amount": entry.amountDescription,
                    "updatedAt": entry.updatedAt
                ]
            )
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.save(samples) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.authorizationUnavailable)
                }
            }
        }
    }
#endif

    private func merge(localEntries: [CalorieEntryPayload], remoteEntries: [CalorieEntryPayload]) -> [CalorieEntryPayload] {
        var mergedByKey: [String: CalorieEntryPayload] = [:]

        remoteEntries.forEach {
            mergedByKey[mergeKey(for: $0)] = $0
        }

        for local in localEntries {
            let key = mergeKey(for: local)
            guard let remote = mergedByKey[key] else {
                mergedByKey[key] = local
                continue
            }

            if local.updatedAt > remote.updatedAt {
                mergedByKey[key] = local
            } else if local.updatedAt == remote.updatedAt {
                // Fallback policy: if timestamps tie, HealthKit remains source of truth.
                mergedByKey[key] = remote
            }
        }

        return Array(mergedByKey.values).sorted { $0.consumedAt > $1.consumedAt }
    }

    private func entriesNeedingPush(localEntries: [CalorieEntryPayload], remoteEntries: [CalorieEntryPayload]) -> [CalorieEntryPayload] {
        let remoteByKey = Dictionary(uniqueKeysWithValues: remoteEntries.map { (mergeKey(for: $0), $0) })
        return localEntries.filter { local in
            let key = mergeKey(for: local)
            guard let remote = remoteByKey[key] else {
                return true
            }
            return local.updatedAt > remote.updatedAt
        }
    }

    private func mergeKey(for payload: CalorieEntryPayload) -> String {
        if let healthKitSampleIdentifier = payload.healthKitSampleIdentifier {
            return "hk-\(healthKitSampleIdentifier)"
        }
        return [
            payload.foodName.lowercased(),
            payload.amountDescription.lowercased(),
            String(Int(payload.calories.rounded())),
            String(Int(payload.consumedAt.timeIntervalSince1970 / 60))
        ].joined(separator: "|")
    }
}
