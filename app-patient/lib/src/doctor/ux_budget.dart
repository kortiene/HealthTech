// Doctor consultation UX budget — anti-regression source of truth (issue #28).
//
// PRD §5 sets a measurable non-functional UX requirement: an UNTRAINED doctor
// must complete a full consultation in < 5 minutes ("ultra-simple, no complex
// menus"). ADR 0002 cites the same "learnable in < 5 minutes" / "single-flow
// UI" as the motivation for the Preact PWA.
//
// This file is the SINGLE SOURCE OF TRUTH for the numeric UX budget that turns
// the canonical consultation journey into checkable invariants. It is documented
// in full in docs/ux/medecin-ux-guidelines.md (§2, §3, §9) — keep the two in sync.
//
// HONESTY: the machine task-time proxy ([taskTimeProxyBudgetMs]) is an
// anti-regression SIGNAL (network excluded, in-process only), NOT a substitute
// for the human < 5 min proof, which comes from the usability test campaign
// (docs/ux/usability-test-protocol.md). Analogous in spirit to PerfBudget (#27).
//
// This introduces NO crypto, protocol, blob-format or data-model change.

/// Budget constants for the doctor consultation journey (issue #28, NFR UX).
abstract final class UxBudget {
  // ── Canonical journey (guide UX §2) ────────────────────────────────────────

  /// The four canonical consultation steps, in order. These machine labels are
  /// FROZEN and shared by the walkthrough guard-rail (test/ux/) and the
  /// task-timing instrumentation ([TaskTiming]). Human-facing microcopy lives in
  /// the UI; these are stable identifiers only — never medical data or PII.
  static const List<String> canonicalSteps = <String>[
    'scan', // viser le QR patient
    'read', // lire le dossier (info vitale en tête)
    'edit', // ajouter une note / ordonnance
    'terminate', // rechiffrer + envoyer/enqueue + wipe
  ];

  /// Maximum interactions/steps of the core consultation flow. Adding a step
  /// REQUIRES bumping this constant explicitly (a conscious review), or the
  /// walkthrough guard-rail fails. Derived from [canonicalSteps].
  static const int maxConsultationSteps = 4;

  /// Maximum distinct screens of the core flow: scan → record view → edit
  /// (terminate returns to the record view, so it adds no new screen). Bumping
  /// this is a conscious "we added a screen to the single flow" decision.
  static const int maxConsultationScreens = 3;

  // ── Critical-information hierarchy (guide UX §3) ────────────────────────────

  /// Normative order of record sections shown to the doctor. Life-critical
  /// information (allergies, chronic conditions, medications) precedes the
  /// consultation history — an allergy must never sit "below the fold" behind an
  /// optional section. The record viewer must render present sections in this
  /// relative order; enforced by the UX-invariant test.
  static const List<String> criticalSectionOrder = <String>[
    'Informations',
    'Allergies',
    'Pathologies chroniques',
    'Médicaments',
    'Consultations',
  ];

  // ── Machine task-time proxy (guide UX §9) ───────────────────────────────────

  /// Generous ceiling (ms) for the DETERMINISTIC, in-process machine task-time
  /// proxy of the whole journey: the sum of scan/read/edit/terminate processing,
  /// NETWORK EXCLUDED. This is an anti-regression signal that catches an
  /// order-of-magnitude slowdown in the flow's app-side work (an accidental
  /// O(n²), a heavy synchronous serialize) — it is emphatically NOT the human
  /// < 5 min proof (see [humanTrainingBudgetMs]). Set far above observed host
  /// timings so it never flakes on shared-runner jitter.
  static const int taskTimeProxyBudgetMs = 2000;

  // ── Human reference (documentation only) ────────────────────────────────────

  /// The PRD §5 human target: < 5 minutes of hands-on time for an untrained
  /// doctor. Present for reference/traceability ONLY — it is validated by the
  /// human usability campaign (docs/ux/usability-test-protocol.md), never by an
  /// automated test. Do NOT assert wall-clock against this value in CI.
  static const int humanTrainingBudgetMs = 5 * 60 * 1000; // 300 000 ms
}
