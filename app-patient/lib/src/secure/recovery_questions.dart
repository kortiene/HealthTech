// Culturally-adapted security questions for the PBKDF2 recovery flow (#12).
//
// These questions are specifically chosen for the Ivorian (Côte d'Ivoire, FR)
// context: they reference institutions, places, and customs that are meaningful
// to a francophone West-African user and are unlikely to be guessable by a
// close third party who shares the same cultural background.
//
// Usage guidance:
//   - The app SHOULD prompt the user to answer at least 3 questions, and MUST
//     pass the answers through [CryptoCore.normalizeRecoveryAnswers] before
//     feeding them to PBKDF2 (diacritic-folding, case-normalisation, separator
//     injection — all handled by the Rust core, G6).
//   - Questions are indexed; the indices chosen by the user are stored alongside
//     the recovery envelope so the correct questions can be re-displayed on the
//     new device.  The answers themselves are NEVER stored.
//   - A minimum of 3 distinct questions is recommended (threat-model control
//     CTRL-04); requiring 5 or more increases brute-force resistance for
//     low-entropy answers.

/// Culturally-adapted security questions for Ivorian (Côte d'Ivoire, FR) users.
///
/// The list contains [kMinRecommendedQuestions] or more entries.  The app
/// should let the user pick at least [kMinRecommendedQuestions] and store the
/// chosen indices alongside the recovery envelope.
const List<String> kRecoveryQuestions = [
  // 0
  "Quel est le nom de l'école primaire que vous avez fréquentée ?",
  // 1
  "Quel est le prénom de votre meilleur(e) ami(e) d'enfance ?",
  // 2
  "Dans quelle ville est né(e) votre père ?",
  // 3
  "Quel est le nom du quartier où vous avez grandi ?",
  // 4
  "Quel est le prénom de votre premier(ère) professeur(e) ?",
  // 5
  "Quel est le nom du marché le plus proche de votre maison d'enfance ?",
  // 6
  "Quel est votre plat ivoirien préféré ?",
  // 7
  "Quel est le nom de votre premier employeur ?",
  // 8
  "Quel est le nom de famille de votre grand-mère maternelle ?",
  // 9
  "Dans quelle ville avez-vous passé votre BEPC ou votre Baccalauréat ?",
];

/// Minimum number of questions the app should require the user to answer.
///
/// Using fewer answers reduces the combined entropy of the recovery secret and
/// weakens brute-force resistance (threat-model control CTRL-04).
const int kMinRecommendedQuestions = 3;
