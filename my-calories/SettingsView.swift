//
//  SettingsView.swift
//  my-calories
//
//  Created by Noah on 8/27/26.
//

import SwiftUI

struct SettingsView: View {
    let profile: UserProfile
    @Binding var hasCompletedQuickStart: Bool
    @Binding var useCloudKitSync: Bool
    @Binding var enableReminders: Bool
    let onOpenQuickStart: () -> Void
    let onRequestHealthKit: () async -> Void

    @State private var isAgeExpanded = false
    @State private var isHeightExpanded = false
    @State private var isWeightExpanded = false

    private struct ActivityLevel: Identifiable {
        let id: String
        let title: String
        let multiplier: Double
    }

    private let activityLevels: [ActivityLevel] = [
        ActivityLevel(id: "sedentary", title: "Sedentary", multiplier: 1.2),
        ActivityLevel(id: "lightlyActive", title: "Lightly Active", multiplier: 1.375),
        ActivityLevel(id: "moderatelyActive", title: "Moderately Active", multiplier: 1.55),
        ActivityLevel(id: "veryActive", title: "Very Active", multiplier: 1.725),
        ActivityLevel(id: "extraActive", title: "Extra Active", multiplier: 1.9)
    ]

    private var selectedActivityLevelID: Binding<String> {
        Binding(
            get: {
                let closest = activityLevels.min {
                    abs($0.multiplier - profile.activityMultiplier) < abs($1.multiplier - profile.activityMultiplier)
                }
                return closest?.id ?? activityLevels[0].id
            },
            set: { newID in
                guard let selected = activityLevels.first(where: { $0.id == newID }) else { return }
                profile.activityMultiplier = selected.multiplier
            }
        )
    }

    var body: some View {
        Form {
            Section("Privacy & Sync") {
                Toggle("Enable CloudKit sync", isOn: $useCloudKitSync)
                Toggle("Enable reminders", isOn: $enableReminders)
                Button("Request HealthKit Access") {
                    Task { await onRequestHealthKit() }
                }
            }

            Section("Quick Start") {
                Label(
                    hasCompletedQuickStart ? "Completed" : "Not completed",
                    systemImage: hasCompletedQuickStart ? "checkmark.circle.fill" : "exclamationmark.circle"
                )
                Button("Open Quick Start") {
                    onOpenQuickStart()
                }
            }

            Section("Profile") {
                Picker(
                    "Biological Sex",
                    selection: Binding(
                        get: { profile.biologicalSex },
                        set: { profile.biologicalSex = $0 }
                    )
                ) {
                    ForEach(BiologicalSex.allCases) { sex in
                        Text(sex.rawValue.capitalized).tag(sex)
                    }
                }

                Button {
                    toggleExpandedPicker(.age)
                } label: {
                    HStack {
                        Text("Age")
                        Spacer()
                        Text("\(profile.age) years")
                            .foregroundStyle(.secondary)
                        Image(systemName: isAgeExpanded ? "chevron.up" : "chevron.down")
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                if isAgeExpanded {
                    Picker("Age", selection: Binding(
                        get: { profile.age },
                        set: { profile.age = $0 }
                    )) {
                        ForEach(13...100, id: \.self) { age in
                            Text("\(age) years").tag(age)
                        }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()
                    .frame(height: 120)
                }

                Button {
                    toggleExpandedPicker(.height)
                } label: {
                    HStack {
                        Text("Height")
                        Spacer()
                        Text("\(Int(profile.heightCm.rounded())) cm")
                            .foregroundStyle(.secondary)
                        Image(systemName: isHeightExpanded ? "chevron.up" : "chevron.down")
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                if isHeightExpanded {
                    Picker("Height", selection: Binding(
                        get: { Int(profile.heightCm.rounded()) },
                        set: { profile.heightCm = Double($0) }
                    )) {
                        ForEach(120...230, id: \.self) { height in
                            Text("\(height) cm").tag(height)
                        }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()
                    .frame(height: 120)
                }

                Button {
                    toggleExpandedPicker(.weight)
                } label: {
                    HStack {
                        Text("Weight")
                        Spacer()
                        Text("\(Int(profile.weightKg.rounded())) kg")
                            .foregroundStyle(.secondary)
                        Image(systemName: isWeightExpanded ? "chevron.up" : "chevron.down")
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                if isWeightExpanded {
                    Picker("Weight", selection: Binding(
                        get: { Int(profile.weightKg.rounded()) },
                        set: { profile.weightKg = Double($0) }
                    )) {
                        ForEach(35...250, id: \.self) { weight in
                            Text("\(weight) kg").tag(weight)
                        }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()
                    .frame(height: 120)
                }

                Picker("Activity Level", selection: selectedActivityLevelID) {
                    ForEach(activityLevels) { level in
                        Text("\(level.title) (\(level.multiplier.formatted(.number.precision(.fractionLength(3)))))")
                            .tag(level.id)
                    }
                }
            }

            Section("Targets") {
                Picker(
                    "Goal",
                    selection: Binding(
                        get: { profile.nutritionGoal },
                        set: { profile.nutritionGoal = $0 }
                    )
                ) {
                    ForEach(NutritionGoal.allCases) { goal in
                        Text(goal.title).tag(goal)
                    }
                }

                if profile.nutritionGoal == .loseWeight {
                    Picker(
                        "Weekly loss pace",
                        selection: Binding(
                            get: { profile.weightLossPace },
                            set: { profile.weightLossPace = $0 }
                        )
                    ) {
                        ForEach(WeightLossPace.allCases) { pace in
                            Text(pace.title).tag(pace)
                        }
                    }
                }

                LabeledContent("Recommended daily") {
                    Text("\(Int(profile.recommendedDailyTarget())) cal")
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Recommended weekly") {
                    Text("\(Int(profile.recommendedWeeklyTarget())) cal")
                        .foregroundStyle(.secondary)
                }

                Button("Use Recommended Targets") {
                    profile.dailyCalorieTarget = profile.recommendedDailyTarget()
                    profile.weeklyCalorieTarget = profile.recommendedWeeklyTarget()
                }

                Stepper(
                    "Daily target: \(Int(profile.dailyCalorieTarget)) cal",
                    value: Binding(
                        get: { profile.dailyCalorieTarget },
                        set: { profile.dailyCalorieTarget = min(max($0, 800), 6000) }
                    ),
                    in: 800...6000,
                    step: 50
                )

                Stepper(
                    "Weekly target: \(Int(profile.weeklyCalorieTarget)) cal",
                    value: Binding(
                        get: { profile.weeklyCalorieTarget },
                        set: { profile.weeklyCalorieTarget = min(max($0, 5600), 42000) }
                    ),
                    in: 5600...42000,
                    step: 100
                )
            }

            Section("Metabolism") {
                Text("Estimated BMR: \(Int(profile.estimatedBMR())) cal/day")
                Text("Estimated TDEE: \(Int(profile.estimatedTDEE())) cal/day")
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isAgeExpanded)
        .animation(.easeInOut(duration: 0.2), value: isHeightExpanded)
        .animation(.easeInOut(duration: 0.2), value: isWeightExpanded)
        .navigationTitle("Settings")
    }

    private enum ExpandedPickerField {
        case age
        case height
        case weight
    }

    private func toggleExpandedPicker(_ field: ExpandedPickerField) {
        withAnimation {
            switch field {
            case .age:
                isAgeExpanded.toggle()
                if isAgeExpanded {
                    isHeightExpanded = false
                    isWeightExpanded = false
                }
            case .height:
                isHeightExpanded.toggle()
                if isHeightExpanded {
                    isAgeExpanded = false
                    isWeightExpanded = false
                }
            case .weight:
                isWeightExpanded.toggle()
                if isWeightExpanded {
                    isAgeExpanded = false
                    isHeightExpanded = false
                }
            }
        }
    }
}
