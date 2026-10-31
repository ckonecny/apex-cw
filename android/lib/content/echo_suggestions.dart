// Gebe-Tempo helpers of the Echo Trainer. The block proposals themselves
// come from the training goals (training_goals.dart); this file only keeps
// the cap's range, shared by the Echo Trainer, the ⚙ sheet and the drills.
import 'training_profile.dart';

/// Lowest Gebe-Tempo cap (echoAnswerWpmMax) the UI offers; 0 = same as
/// Hören. Same floor as the listening speed (TrainingProfile.minWpm).
const int kGiveWpmMin = TrainingProfile.minWpm;

/// A stored cap, sanitised: 0 stays "same as Hören", older values below
/// [kGiveWpmMin] are raised to it.
int kGiveWpmCap(int v) => v <= 0 ? 0 : v.clamp(kGiveWpmMin, 60);

