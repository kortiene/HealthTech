// Unit tests for UxBudget constants (issue #28, Livrable C — source of vérité).
//
// These tests ARE the walkthrough guard-rail's integrity anchor: any change to
// the canonical step list, screen count, or timing proxy requires updating this
// file — a deliberate review gate matching the philosophy of PerfBudget (#27).
//
// HONESTY: humanTrainingBudgetMs is a documentation-only reference; we do NOT
// assert wall-clock against it in CI. That proof comes from the human usability
// campaign (docs/ux/usability-test-protocol.md).

import 'package:flutter_test/flutter_test.dart';

import 'package:app_patient/src/doctor/ux_budget.dart';

void main() {
  group('UxBudget — canonical steps', () {
    test('canonicalSteps.length == maxConsultationSteps', () {
      expect(UxBudget.canonicalSteps.length, UxBudget.maxConsultationSteps);
    });

    test('canonicalSteps are in consultation-flow order', () {
      expect(UxBudget.canonicalSteps, ['scan', 'read', 'edit', 'terminate']);
    });

    test('maxConsultationSteps == 4 (PRD §5 canonical 4-step journey)', () {
      expect(UxBudget.maxConsultationSteps, 4);
    });

    test('no duplicate labels in canonicalSteps', () {
      expect(UxBudget.canonicalSteps.toSet().length,
          UxBudget.canonicalSteps.length);
    });
  });

  group('UxBudget — screen budget', () {
    test('maxConsultationScreens == 3 (scan / record / edit; terminate = pop)',
        () {
      expect(UxBudget.maxConsultationScreens, 3);
    });

    test(
        'maxConsultationScreens < maxConsultationSteps (terminate is a pop, not a push)',
        () {
      expect(UxBudget.maxConsultationScreens,
          lessThan(UxBudget.maxConsultationSteps));
    });
  });

  group('UxBudget — critical section order (guide UX §3)', () {
    test('criticalSectionOrder starts with Informations', () {
      expect(UxBudget.criticalSectionOrder.first, 'Informations');
    });

    test('Allergies appears before Consultations — life-critical info first',
        () {
      final allergiesIdx = UxBudget.criticalSectionOrder.indexOf('Allergies');
      final consultationsIdx =
          UxBudget.criticalSectionOrder.indexOf('Consultations');
      expect(allergiesIdx, greaterThan(-1),
          reason: 'Allergies must be in the list');
      expect(consultationsIdx, greaterThan(-1),
          reason: 'Consultations must be in the list');
      expect(allergiesIdx, lessThan(consultationsIdx));
    });

    test('Pathologies chroniques appears before Médicaments', () {
      final pathologiesIdx =
          UxBudget.criticalSectionOrder.indexOf('Pathologies chroniques');
      final medicamentsIdx =
          UxBudget.criticalSectionOrder.indexOf('Médicaments');
      expect(pathologiesIdx, lessThan(medicamentsIdx));
    });

    test('Médicaments appears before Consultations', () {
      final medicamentsIdx =
          UxBudget.criticalSectionOrder.indexOf('Médicaments');
      final consultationsIdx =
          UxBudget.criticalSectionOrder.indexOf('Consultations');
      expect(medicamentsIdx, lessThan(consultationsIdx));
    });
  });

  group('UxBudget — timing constants', () {
    test('taskTimeProxyBudgetMs is positive', () {
      expect(UxBudget.taskTimeProxyBudgetMs, greaterThan(0));
    });

    test('humanTrainingBudgetMs == 5 min (300 000 ms — PRD §5 reference)', () {
      expect(UxBudget.humanTrainingBudgetMs, 5 * 60 * 1000);
    });

    test(
        'taskTimeProxyBudgetMs << humanTrainingBudgetMs (machine proxy != human proof)',
        () {
      // The machine proxy is a generous in-process ceiling (2 s), orders of
      // magnitude below the human target (5 min = 300 s). If this test fails,
      // the constants were accidentally swapped.
      expect(UxBudget.taskTimeProxyBudgetMs,
          lessThan(UxBudget.humanTrainingBudgetMs));
    });
  });
}
