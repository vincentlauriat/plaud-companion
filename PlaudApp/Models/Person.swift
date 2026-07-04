import Foundation

/// Une personne = un libellé d'interlocuteur (speaker) issu de la diarization Plaud,
/// agrégé sur l'ensemble des réunions indexées où ce libellé apparaît.
///
/// Limite assumée : la diarization Plaud n'est pas nommée (« Speaker 1 », « Speaker 2 »…).
/// Un même libellé peut désigner des personnes différentes d'une réunion à l'autre ; pour
/// obtenir de vrais noms cohérents, renommer les interlocuteurs côté Plaud puis rafraîchir.
struct Person: Identifiable, Hashable {
    /// Le libellé du speaker sert d'identité stable.
    var id: String { name }
    let name: String
    let recordingIDs: [String]

    var meetingCount: Int { recordingIDs.count }
}
