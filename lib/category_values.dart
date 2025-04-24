enum HKCategoryValue {
  notApplicable(0);

  factory HKCategoryValue.fromValue(int value) {
    return HKCategoryValue.values.firstWhere((e) => e.value == value);
  }

  const HKCategoryValue(this.value);
  final num value;
}

enum HKCategoryValueAppetiteChanges {
  unspecified(0),
  noChange(1),
  decreased(2),
  increased(3);

  factory HKCategoryValueAppetiteChanges.fromValue(int value) {
    return HKCategoryValueAppetiteChanges.values
        .firstWhere((e) => e.value == value);
  }

  const HKCategoryValueAppetiteChanges(this.value);
  final num value;
}

enum HKCategoryValueAppleStandHour {
  stood(0),
  idle(1);

  factory HKCategoryValueAppleStandHour.fromValue(int value) {
    return HKCategoryValueAppleStandHour.values
        .firstWhere((e) => e.value == value);
  }

  const HKCategoryValueAppleStandHour(this.value);
  final num value;
}

enum HKCategoryValueAppleWalkingSteadinessEvent {
  initialLow(1),
  initialVeryLow(2),
  repeatLow(3),
  repeatVeryLow(4);

  factory HKCategoryValueAppleWalkingSteadinessEvent.fromValue(int value) {
    return HKCategoryValueAppleWalkingSteadinessEvent.values
        .firstWhere((e) => e.value == value);
  }

  const HKCategoryValueAppleWalkingSteadinessEvent(this.value);
  final num value;
}

enum HKCategoryValueCervicalMucusQuality {
  dry(1),
  sticky(2),
  creamy(3),
  watery(4),
  eggWhite(5);

  factory HKCategoryValueCervicalMucusQuality.fromValue(int value) {
    return HKCategoryValueCervicalMucusQuality.values
        .firstWhere((e) => e.value == value);
  }

  const HKCategoryValueCervicalMucusQuality(this.value);
  final num value;
}

enum HKCategoryValueContraceptive {
  unspecified(1),
  implant(2),
  injection(3),
  intrauterineDevice(4),
  intravaginalRing(5),
  oral(6),
  patch(7);

  factory HKCategoryValueContraceptive.fromValue(int value) {
    return HKCategoryValueContraceptive.values
        .firstWhere((e) => e.value == value);
  }

  const HKCategoryValueContraceptive(this.value);
  final num value;
}

enum HKCategoryValueEnvironmentalAudioExposureEvent {
  momentaryLimit(1);

  factory HKCategoryValueEnvironmentalAudioExposureEvent.fromValue(int value) {
    return HKCategoryValueEnvironmentalAudioExposureEvent.values
        .firstWhere((e) => e.value == value);
  }

  const HKCategoryValueEnvironmentalAudioExposureEvent(this.value);
  final num value;
}

enum HKCategoryValueHeadphoneAudioExposureEvent {
  sevenDayLimit(1);

  factory HKCategoryValueHeadphoneAudioExposureEvent.fromValue(int value) {
    return HKCategoryValueHeadphoneAudioExposureEvent.values
        .firstWhere((e) => e.value == value);
  }

  const HKCategoryValueHeadphoneAudioExposureEvent(this.value);
  final num value;
}

enum HKCategoryValueLowCardioFitnessEvent {
  lowFitness(1);

  factory HKCategoryValueLowCardioFitnessEvent.fromValue(int value) {
    return HKCategoryValueLowCardioFitnessEvent.values
        .firstWhere((e) => e.value == value);
  }

  const HKCategoryValueLowCardioFitnessEvent(this.value);
  final num value;
}

enum HKCategoryValueMenstrualFlow {
  unspecified(1),
  light(2),
  medium(3),
  heavy(4),
  none(5);

  factory HKCategoryValueMenstrualFlow.fromValue(int value) {
    return HKCategoryValueMenstrualFlow.values
        .firstWhere((e) => e.value == value);
  }

  const HKCategoryValueMenstrualFlow(this.value);
  final num value;
}

enum HKCategoryValueOvulationTestResult {
  negative(1),
  luteinizingHormoneSurge(2),
  indeterminate(3),
  estrogenSurge(4);

  factory HKCategoryValueOvulationTestResult.fromValue(int value) {
    return HKCategoryValueOvulationTestResult.values
        .firstWhere((e) => e.value == value);
  }

  const HKCategoryValueOvulationTestResult(this.value);
  final num value;
}

enum HKCategoryValuePregnancyTestResult {
  negative(1),
  positive(2),
  indeterminate(3);

  factory HKCategoryValuePregnancyTestResult.fromValue(int value) {
    return HKCategoryValuePregnancyTestResult.values
        .firstWhere((e) => e.value == value);
  }

  const HKCategoryValuePregnancyTestResult(this.value);
  final num value;
}

enum HKCategoryValuePresence {
  present(0),
  notPresent(1);

  factory HKCategoryValuePresence.fromValue(int value) {
    return HKCategoryValuePresence.values.firstWhere((e) => e.value == value);
  }

  const HKCategoryValuePresence(this.value);
  final num value;
}

enum HKCategoryValueProgesteroneTestResult {
  negative(1),
  positive(2),
  indeterminate(3);

  factory HKCategoryValueProgesteroneTestResult.fromValue(int value) {
    return HKCategoryValueProgesteroneTestResult.values
        .firstWhere((e) => e.value == value);
  }

  const HKCategoryValueProgesteroneTestResult(this.value);
  final num value;
}

enum HKCategoryValueSeverity {
  unspecified(0),
  notPresent(1),
  mild(2),
  moderate(3),
  severe(4);

  factory HKCategoryValueSeverity.fromValue(int value) {
    return HKCategoryValueSeverity.values.firstWhere((e) => e.value == value);
  }

  const HKCategoryValueSeverity(this.value);
  final num value;
}

enum HKCategoryValueSleepAnalysis {
  inBed(0),
  asleepUnspecified(1),
  awake(2),
  asleepCore(3),
  asleepDeep(4),
  asleepREM(5);

  factory HKCategoryValueSleepAnalysis.fromValue(int value) {
    return HKCategoryValueSleepAnalysis.values
        .firstWhere((e) => e.value == value);
  }

  const HKCategoryValueSleepAnalysis(this.value);
  final num value;
}
