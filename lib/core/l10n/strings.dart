// Simple string map for English/French localisation.
// Usage: S.of(context).bookPickup

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppStrings {
  final bool isFrench;
  const AppStrings({this.isFrench = false});

  // ── Auth ──────────────────────────────────────────────────────────────────
  String get appName              => isFrench ? 'BinLink Eco' : 'BinLink Eco';
  String get welcome              => isFrench ? 'Bienvenue sur BinLink Eco' : 'Welcome to BinLink Eco';
  String get signIn               => isFrench ? 'Se connecter' : 'Sign In';
  String get signUp               => isFrench ? 'S\'inscrire' : 'Sign Up';
  String get continueWithGoogle   => isFrench ? 'Continuer avec Google' : 'Continue with Google';
  String get forgotPassword       => isFrench ? 'Mot de passe oublié ?' : 'Forgot password?';
  String get logout               => isFrench ? 'Déconnexion' : 'Log Out';
  String get fullName             => isFrench ? 'Nom complet' : 'Full Name';
  String get emailAddress         => isFrench ? 'Adresse e-mail' : 'Email Address';
  String get password             => isFrench ? 'Mot de passe' : 'Password';
  String get confirmPassword      => isFrench ? 'Confirmer le mot de passe' : 'Confirm Password';
  String get createAccount        => isFrench ? 'Créer un compte' : 'Create Account';
  String get alreadyHaveAccount   => isFrench ? 'Vous avez déjà un compte ? ' : 'Already have an account? ';
  String get dontHaveAccount      => isFrench ? 'Pas encore de compte ? ' : 'Don\'t have an account? ';
  String get resetPassword        => isFrench ? 'Réinitialiser le mot de passe' : 'Reset Password';
  String get sendResetLink        => isFrench ? 'Envoyer le lien de réinitialisation' : 'Send Reset Link';

  // ── Navigation labels ─────────────────────────────────────────────────────
  String get home                 => isFrench ? 'Accueil' : 'Home';
  String get map                  => isFrench ? 'Carte' : 'Map';

  // ── Household Home ────────────────────────────────────────────────────────
  String get hello                => isFrench ? 'Bonjour' : 'Hello';
  String get bookPickup           => isFrench ? 'Planifier un ramassage' : 'Book a Pickup';
  String get schedulePickup       => isFrench ? 'Planifier' : 'Schedule';
  String get quickBook            => isFrench ? 'Réservation rapide' : 'Quick Book';
  String get trackPickup          => isFrench ? 'Suivre mon ramassage' : 'Track My Pickup';
  String get activeBooking        => isFrench ? 'Ramassage en cours' : 'Active Pickup';
  String get collectors           => isFrench ? 'Collecteurs' : 'Collectors';
  String get onlineCollectors     => isFrench ? 'Collecteurs disponibles' : 'Online Collectors';
  String get noActiveBooking      => isFrench ? 'Aucune réservation active' : 'No active booking';
  String get ecoPoints            => isFrench ? 'Points Éco' : 'Eco Points';
  String get kgRecycled           => isFrench ? 'kg Recyclés' : 'kg Recycled';
  String get viewHistory          => isFrench ? 'Voir l\'historique' : 'View History';

  // ── Booking Wizard ────────────────────────────────────────────────────────
  String get bookAPickup          => isFrench ? 'Réserver un ramassage' : 'Book a Pickup';
  String get category             => isFrench ? 'Catégorie' : 'Category';
  String get volume               => isFrench ? 'Volume' : 'Volume';
  String get photos               => isFrench ? 'Photos' : 'Photos';
  String get schedule             => isFrench ? 'Horaire' : 'Schedule';
  String get address              => isFrench ? 'Adresse' : 'Address';
  String get review               => isFrench ? 'Résumé' : 'Review';
  String get next                 => isFrench ? 'Suivant' : 'Next';
  String get back                 => isFrench ? 'Retour' : 'Back';
  String get confirm              => isFrench ? 'Confirmer' : 'Confirm';
  String get pickupNow            => isFrench ? 'Maintenant' : 'Now';
  String get pickupLater          => isFrench ? 'Plus tard' : 'Later';
  String get totalAmount          => isFrench ? 'Montant total' : 'Total';
  String get extraBags            => isFrench ? 'Sacs supplémentaires' : 'Extra Bags';
  String get wasteType            => isFrench ? 'Type de déchets' : 'Waste Type';
  String get addPhoto             => isFrench ? 'Ajouter une photo' : 'Add Photo';
  String get photoOptional        => isFrench ? 'Photos optionnelles — aident le collecteur' : 'Optional — helps the collector';
  String get pickupAddress        => isFrench ? 'Adresse de ramassage' : 'Pickup Address';
  String get addressNotes         => isFrench ? 'Instructions supplémentaires' : 'Gate / access notes';
  String get searchAddress        => isFrench ? 'Rechercher une adresse' : 'Search address';
  String get frequency            => isFrench ? 'Fréquence' : 'Frequency';
  String get oneTime              => isFrench ? 'Une fois' : 'One-time';
  String get weekly               => isFrench ? 'Hebdomadaire' : 'Weekly';
  String get biweekly             => isFrench ? 'Bihebdomadaire' : 'Bi-weekly';
  String get monthly              => isFrench ? 'Mensuel' : 'Monthly';

  // ── Home tab extras ───────────────────────────────────────────────────────
  String get requestNow           => isFrench ? 'Commander' : 'Request Now';
  String get arrival15min         => isFrench ? '~15 min' : '~15 min arrival';
  String get pickDate             => isFrench ? 'Choisir une date' : 'Pick a date';
  String get tapToTrack           => isFrench ? 'Toucher pour suivre' : 'Tap to track your pickup';
  String get searchAreaLandmark   => isFrench ? 'Chercher un quartier, rue...' : 'Search area, street, landmark...';
  String get nearbyCount          => isFrench ? 'à proximité' : 'nearby';
  String get allBookings          => isFrench ? 'Toutes les réservations' : 'All Bookings';
  String get activeSubscriptionsTitle => isFrench ? 'Abonnements actifs' : 'Active Subscriptions';
  String get noPickupsYetSub      => isFrench ? 'Vos ramassages apparaîtront ici' : 'Your completed pickups will appear here';
  String get totalPickupsLabel    => isFrench ? 'ramassages au total' : 'total pickups';
  String get bookingDetails       => isFrench ? 'Détails de la réservation' : 'Booking Details';
  String get totalPaid            => isFrench ? 'Total payé' : 'Total Paid';
  String get yourImpact           => isFrench ? 'Votre impact environnemental' : 'Your Environmental Impact';
  String get tellUsWhyCancel      => isFrench ? 'Dites-nous pourquoi — cela nous aide.' : 'Tell us why — this helps us improve.';

  // ── Collector map extras ──────────────────────────────────────────────────
  String get onlineAccepting      => isFrench ? 'En ligne — Disponible' : 'Online — Accepting jobs';
  String get activePickupBanner   => isFrench ? 'Ramassage actif' : 'Active Pickup';

  // ── Payment ───────────────────────────────────────────────────────────────
  String get payment              => isFrench ? 'Paiement' : 'Payment';
  String get payNow               => isFrench ? 'Payer maintenant' : 'Pay Now';
  String get confirmBooking       => isFrench ? 'Confirmer la réservation' : 'Confirm Booking';
  String get momoNumber           => isFrench ? 'Numéro MoMo' : 'MoMo Number';
  String get howToPay             => isFrench ? 'Comment payer' : 'How to pay';
  String get payInCash            => isFrench ? 'Payer en espèces' : 'Pay in Cash';
  String get paymentFailed        => isFrench ? 'Paiement échoué. Vérifiez votre numéro et réessayez.' : 'Payment failed. Check your number and try again.';
  String get pickupConfirmed      => isFrench ? 'Ramassage confirmé !' : 'Pickup Confirmed!';
  String get collectorBeingAssigned => isFrench ? 'Un collecteur est en route. Arrivée prévue : ~15 min.' : 'A collector is being assigned. ETA ~15 minutes.';
  String get bookingRef           => isFrench ? 'Référence' : 'Booking Ref';
  String get amountPaid           => isFrench ? 'Montant payé' : 'Amount Paid';
  String get downloadReceipt      => isFrench ? 'Télécharger le reçu' : 'Download Receipt';
  String get backToHome           => isFrench ? 'Retour à l\'accueil' : 'Back to Home';

  // ── History / Bookings ────────────────────────────────────────────────────
  String get history              => isFrench ? 'Historique' : 'History';
  String get subscriptions        => isFrench ? 'Abonnements' : 'Subscriptions';
  String get noBookingsYet        => isFrench ? 'Aucune réservation pour l\'instant' : 'No bookings yet';
  String get bookFirstPickup      => isFrench ? 'Réservez votre premier ramassage' : 'Book your first pickup';
  String get pending              => isFrench ? 'En attente' : 'Pending';
  String get accepted             => isFrench ? 'Accepté' : 'Accepted';
  String get enRoute              => isFrench ? 'En route' : 'En Route';
  String get arrived              => isFrench ? 'Arrivé' : 'Arrived';
  String get completed            => isFrench ? 'Terminé' : 'Completed';
  String get cancelled            => isFrench ? 'Annulé' : 'Cancelled';
  String get cancelBooking        => isFrench ? 'Annuler la réservation' : 'Cancel Booking';
  String get cancelReason         => isFrench ? 'Raison de l\'annulation' : 'Reason for cancellation';
  String get cancelConfirm        => isFrench ? 'Annuler la réservation ?' : 'Cancel this booking?';
  String get keepBooking          => isFrench ? 'Garder' : 'Keep it';
  String get yesCancel            => isFrench ? 'Oui, annuler' : 'Yes, cancel';
  String get bookingCancelled     => isFrench ? 'Réservation annulée' : 'Booking cancelled';

  // Cancel reasons
  List<String> get cancelReasons => isFrench
      ? ['Je n\'en ai plus besoin', 'Collecteur trop long', 'J\'ai trouvé une autre solution', 'Mauvaise adresse', 'Autre']
      : ['I no longer need it', 'Collector taking too long', 'Found another solution', 'Wrong address entered', 'Other'];

  // ── Profile ───────────────────────────────────────────────────────────────
  String get profile              => isFrench ? 'Profil' : 'Profile';
  String get account              => isFrench ? 'Compte' : 'Account';
  String get support              => isFrench ? 'Support' : 'Support';
  String get helpSupport          => isFrench ? 'Aide et support' : 'Help & Support';
  String get privacyPolicy        => isFrench ? 'Politique de confidentialité' : 'Privacy Policy';
  String get householdMember      => isFrench ? 'Membre ménage' : 'Household Member';
  String get collectorLabel       => isFrench ? 'Collecteur' : 'Collector';
  String get vehicleDetails       => isFrench ? 'Détails du véhicule' : 'Vehicle Details';
  String get earningsWallet       => isFrench ? 'Revenus et portefeuille' : 'Earnings & Wallet';
  String get editProfile          => isFrench ? 'Modifier le profil' : 'Edit Profile';
  String get notifications        => isFrench ? 'Notifications' : 'Notifications';
  String get preferences          => isFrench ? 'Préférences' : 'Preferences';
  String get darkMode             => isFrench ? 'Mode sombre' : 'Dark Mode';
  String get language             => isFrench ? 'Langue' : 'Language';
  String get savedAddresses       => isFrench ? 'Adresses enregistrées' : 'Saved Addresses';
  String get help                 => isFrench ? 'Aide' : 'Help';
  String get privacy              => isFrench ? 'Confidentialité' : 'Privacy';
  String get termsOfService       => isFrench ? 'Conditions d\'utilisation' : 'Terms of Service';
  String get rateApp              => isFrench ? 'Évaluer l\'app' : 'Rate the App';
  String get version              => isFrench ? 'Version' : 'Version';
  String get dangerZone           => isFrench ? 'Zone dangereuse' : 'Danger Zone';
  String get deleteAccount        => isFrench ? 'Supprimer le compte' : 'Delete Account';
  String get save                 => isFrench ? 'Enregistrer' : 'Save';
  String get cancel               => isFrench ? 'Annuler' : 'Cancel';

  // ── Tracking ──────────────────────────────────────────────────────────────
  String get liveTracking         => isFrench ? 'Suivi en direct' : 'Live Tracking';
  String get collectorOnWay       => isFrench ? 'Collecteur en route' : 'Collector On the Way';
  String get collectorArrived     => isFrench ? 'Collecteur arrivé' : 'Collector Arrived';
  String get pickupComplete       => isFrench ? 'Ramassage terminé' : 'Pickup Complete';
  String get chat                 => isFrench ? 'Discussion' : 'Chat';
  String get typeMessage          => isFrench ? 'Écrire un message…' : 'Type a message…';
  String get rateCollector        => isFrench ? 'Évaluer le collecteur' : 'Rate Your Collector';
  String get submitRating         => isFrench ? 'Envoyer l\'évaluation' : 'Submit Rating';

  // ── Collector ─────────────────────────────────────────────────────────────
  String get goOnline             => isFrench ? 'Se mettre en ligne' : 'Go Online';
  String get goOffline            => isFrench ? 'Se déconnecter' : 'Go Offline';
  String get online               => isFrench ? 'En ligne' : 'Online';
  String get offline              => isFrench ? 'Hors ligne' : 'Offline';
  String get newRequest           => isFrench ? 'Nouvelle demande' : 'New Request';
  String get acceptJob            => isFrench ? 'Accepter' : 'Accept';
  String get declineJob           => isFrench ? 'Refuser' : 'Decline';
  String get pickups              => isFrench ? 'Ramassages' : 'Pickups';
  String get earnings             => isFrench ? 'Revenus' : 'Earnings';
  String get todayEarnings        => isFrench ? 'Revenus aujourd\'hui' : 'Today\'s Earnings';
  String get totalPickups         => isFrench ? 'Total ramassages' : 'Total Pickups';
  String get requestPayout        => isFrench ? 'Demander un paiement' : 'Request Payout';
  String get startRoute           => isFrench ? 'Démarrer le trajet' : 'Start Route';
  String get markArrived          => isFrench ? 'Marquer arrivé' : 'Mark Arrived';
  String get completePickup       => isFrench ? 'Terminer le ramassage' : 'Complete Pickup';
  String get takeBefore           => isFrench ? 'Photo avant ramassage' : 'Before Photo';
  String get takeAfter            => isFrench ? 'Photo après ramassage' : 'After Photo';
  String get reportException      => isFrench ? 'Signaler un problème' : 'Report Issue';
  String get assigned             => isFrench ? 'Assigné' : 'Assigned';
  String get vehicle              => isFrench ? 'Véhicule' : 'Vehicle';
  String get licensePlate         => isFrench ? 'Plaque d\'immatriculation' : 'License Plate';
}

// ── Provider ─────────────────────────────────────────────────────────────────

class AppStringsProvider extends ChangeNotifier {
  AppStrings _strings = const AppStrings();
  String _langCode = 'English';

  AppStrings get strings => _strings;
  String get langCode => _langCode;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final lang = prefs.getString('language') ?? 'English';
    _setLang(lang, notify: false);
  }

  Future<void> setLanguage(String lang) async {
    _setLang(lang);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', lang);
  }

  void _setLang(String lang, {bool notify = true}) {
    _langCode = lang;
    _strings = AppStrings(isFrench: lang == 'Français');
    if (notify) notifyListeners();
  }
}

// ── Convenience accessor ──────────────────────────────────────────────────────

class S {
  static AppStrings of(BuildContext context) {
    return context.watch<AppStringsProvider>().strings;
  }

  static AppStrings read(BuildContext context) {
    return context.read<AppStringsProvider>().strings;
  }
}
