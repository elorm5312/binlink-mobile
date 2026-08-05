import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../../core/design_system/household_design_system.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/places_service.dart';
import '../providers/household_provider.dart';
import 'payment_screen.dart';
import 'tracking_screen.dart';

const _kPrices = {'SMALL': 40.0, 'MEDIUM': 50.0, 'LARGE': 60.0};
const _kBagPrice = 16.0;
const _kServiceFee = 2.0;

class BookScreen extends StatefulWidget {
  const BookScreen({
    super.key,
    this.mode = 'immediate',
    this.myPos,
    this.preferredCollectorId,
    this.preferredCollectorName,
  });
  final String mode;
  final ll.LatLng? myPos;
  final String? preferredCollectorId;
  final String? preferredCollectorName;

  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> {
  final _pageCtrl = PageController();
  int _step = 0;
  bool _loading = false;
  String? _error;

  // Step 1
  String _category = 'HOUSEHOLD';

  // Step 2
  String _binSize = 'MEDIUM';
  int _extraBags = 0;
  double _weightKg = 100;

  // Step 2 — bulky items (photos so the collector can see the load)
  final List<XFile> _bulkyPhotos = [];
  final _bulkyDescCtrl = TextEditingController();

  /// HOUSEHOLD waste has fixed bin-size pricing; everything else (recyclables
  /// and bulky items) is priced by the collector on arrival.
  bool get _isFixed => _category == 'HOUSEHOLD';
  bool get _isBulky => _category == 'BULKY';

  // Step 3
  late bool _isImmediate;
  DateTime? _scheduledDate;
  String _timePref = 'MORNING';
  String _frequency = 'ONE_TIME';

  // Step 4
  final _addrCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  double? _lat;
  double? _lng;
  bool _locLoading = false;

  // Step 5
  String _payment = 'CASH';
  final _promoCtrl = TextEditingController();
  double _promoDiscount = 0;
  String? _promoCode;
  bool _promoChecking = false;

  @override
  void initState() {
    super.initState();
    _isImmediate = widget.mode == 'immediate';
    if (widget.myPos != null) {
      _lat = widget.myPos!.latitude;
      _lng = widget.myPos!.longitude;
      _reverseGeocode();
    } else {
      _loadLocation();
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _addrCtrl.dispose();
    _notesCtrl.dispose();
    _promoCtrl.dispose();
    _bulkyDescCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLocation() async {
    setState(() => _locLoading = true);
    try {
      final pos = await LocationService.getCurrentPosition();
      if (pos != null && mounted) {
        _lat = pos.latitude;
        _lng = pos.longitude;
        await _reverseGeocode();
      }
    } finally {
      if (mounted) setState(() => _locLoading = false);
    }
  }

  Future<void> _reverseGeocode() async {
    if (_lat == null || _lng == null) return;
    setState(() => _locLoading = true);
    final addr = await PlacesService.reverseGeocode(_lat!, _lng!);
    if (mounted) {
      _addrCtrl.text = addr ?? 'Current GPS location';
      setState(() => _locLoading = false);
    }
  }

  double get _base => _kPrices[_binSize] ?? 40.0;
  double get _bagsTotal => _extraBags * _kBagPrice;
  double get _grossTotal => _base + _bagsTotal + _kServiceFee;
  double get _total => (_grossTotal - _promoDiscount).clamp(0, double.infinity).toDouble();

  Future<void> _pickBulkyPhoto(ImageSource source) async {
    if (_bulkyPhotos.length >= 8) return;
    final img = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 82);
    if (img != null && mounted) setState(() => _bulkyPhotos.add(img));
  }

  Future<void> _applyPromo() async {
    final code = _promoCtrl.text.trim();
    if (code.isEmpty || _promoChecking) return;
    setState(() => _promoChecking = true);
    final result = await context.read<HouseholdProvider>().validatePromo(code, _grossTotal);
    if (!mounted) return;
    setState(() {
      _promoChecking = false;
      if (result != null) {
        _promoDiscount = ((result['discount'] as num?) ?? 0).toDouble();
        _promoCode = code.toUpperCase();
      } else {
        _promoDiscount = 0;
        _promoCode = null;
      }
    });
    final err = context.read<HouseholdProvider>().promoError;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: HouseholdColors.ecoGreen,
        content: Text('Promo applied — GHS ${_promoDiscount.toStringAsFixed(2)} off')));
    }
  }

  bool get _canNext {
    switch (_step) {
      case 1: return !_isBulky || _bulkyPhotos.isNotEmpty;
      case 2: return _isImmediate || _scheduledDate != null;
      case 3: return _addrCtrl.text.trim().isNotEmpty;
      default: return true;
    }
  }

  void _goNext() {
    if (_step < 4) {
      _pageCtrl.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeInOut);
      setState(() { _step++; _error = null; });
      HapticFeedback.lightImpact();
    } else {
      _submit();
    }
  }

  void _goBack() {
    if (_step > 0) {
      _pageCtrl.previousPage(duration: const Duration(milliseconds: 280), curve: Curves.easeInOut);
      setState(() { _step--; _error = null; });
    } else {
      Navigator.maybePop(context);
    }
  }

  Future<void> _submit() async {
    final addr = _addrCtrl.text.trim();
    if (addr.isEmpty) {
      setState(() => _error = 'Please enter your pickup address.');
      return;
    }
    if (_lat == null || _lng == null) {
      setState(() => _error = 'Location not available. Tap "Use my location" in step 4.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    final prov = context.read<HouseholdProvider>();

    // Upload any attached rubbish photos first so the collector can see the
    // load the moment the job is dispatched (required for bulky, optional for
    // every other category).
    List<String>? photoUrls;
    if (_bulkyPhotos.isNotEmpty) {
      photoUrls = [];
      for (final photo in _bulkyPhotos) {
        final url = await prov.uploadBulkyPhoto(photo.path);
        if (url != null) photoUrls.add(url);
      }
      if (photoUrls.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Photo upload failed. Please check your connection and try again.';
        });
        return;
      }
    }

    final bulkyDesc = _bulkyDescCtrl.text.trim();
    final notes = [
      if (_isBulky && bulkyDesc.isNotEmpty) 'Items: $bulkyDesc',
      if (_notesCtrl.text.trim().isNotEmpty) _notesCtrl.text.trim(),
    ].join('\n');

    final booking = await prov.createBooking(
      binSize: _binSize,
      extraBags: _isFixed ? _extraBags : 0,
      pickupAddress: addr,
      pickupLat: _lat!,
      pickupLng: _lng!,
      // Negotiated bookings are always paid on pickup, directly to the collector.
      paymentMethod: _isFixed ? _payment : 'CASH',
      wasteCategory: _category,
      timePreference: _isImmediate ? null : _timePref,
      estimatedWeightKg: _weightKg > 0 ? _weightKg : null,
      addressNotes: notes.isNotEmpty ? notes : null,
      scheduledDate: _isImmediate ? null : _scheduledDate,
      frequency: _frequency != 'ONE_TIME' ? _frequency : null,
      preferredCollectorId: widget.preferredCollectorId,
      promoCode: _isFixed ? _promoCode : null,
      pricingMode: _isFixed ? null : 'NEGOTIATED',
      bulkyPhotos: photoUrls,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (booking == null) {
      // An earlier pickup is still active — offer to view or cancel it rather
      // than leaving the user stuck with an error they can't resolve.
      final conflictId = prov.conflictBookingId;
      if (conflictId != null) {
        setState(() => _error = null);
        await _handleActivePickupConflict(prov, conflictId);
        return;
      }
      setState(() => _error = prov.error ?? 'Failed to create booking. Please try again.');
      return;
    }
    prov.listenToBooking(booking['id'] as String);
    // Negotiated bookings have nothing to pay in-app — the price is agreed on
    // arrival and paid directly to the collector.
    if (_payment == 'CASH' || !_isFixed) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => TrackingScreen(booking: booking),
      ));
    } else {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => PaymentScreen(booking: booking),
      ));
    }
  }

  /// Shown when booking fails because an earlier pickup is still active.
  Future<void> _handleActivePickupConflict(HouseholdProvider prov, String conflictId) async {
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HouseholdColors.card,
        title: Text('Pickup already in progress',
            style: HouseholdType.title.copyWith(color: HouseholdColors.charcoal)),
        content: Text(
          'You already have an active pickup. You can view it, or cancel it and place this new one.',
          style: HouseholdType.body.copyWith(color: HouseholdColors.charcoal),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel_old'),
            child: const Text('Cancel it & rebook'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: HouseholdColors.primary),
            onPressed: () => Navigator.pop(ctx, 'view'),
            child: const Text('View pickup'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;

    if (choice == 'view') {
      setState(() => _loading = true);
      final existing = await prov.fetchBooking(conflictId);
      if (!mounted) return;
      setState(() => _loading = false);
      if (existing != null) {
        prov.listenToBooking(conflictId);
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => TrackingScreen(booking: existing),
        ));
      } else {
        setState(() => _error = 'Could not load your active pickup. Please check your history.');
      }
    } else if (choice == 'cancel_old') {
      setState(() => _loading = true);
      final ok = await prov.cancelBooking(conflictId, reason: 'Replaced by a new booking');
      if (!mounted) return;
      setState(() => _loading = false);
      if (ok) {
        await _submit(); // retry the new booking now that the old one is gone
      } else {
        setState(() => _error = prov.error ?? 'Could not cancel the active pickup.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HouseholdColors.sand,
      body: SafeArea(
        child: Column(children: [
          _BookHeader(step: _step, onClose: _goBack),
          const SizedBox(height: 12),
          if (widget.preferredCollectorName != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: HouseholdColors.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: HouseholdColors.primary.withAlpha(60)),
                ),
                child: Row(children: [
                  HIcon('star', color: HouseholdColors.primary, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Requesting ${widget.preferredCollectorName} first',
                        style: HouseholdType.caption.copyWith(
                            color: HouseholdColors.charcoal, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 10),
          ],
          _StepBar(step: _step),
          const SizedBox(height: 12),
          Expanded(
            child: PageView(
              controller: _pageCtrl,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _Step1(category: _category, onChanged: (v) => setState(() => _category = v)),
                _Step2(
                  category: _category,
                  binSize: _binSize,
                  extraBags: _extraBags,
                  weightKg: _weightKg,
                  bulkyPhotos: _bulkyPhotos,
                  bulkyDescCtrl: _bulkyDescCtrl,
                  onBin: (v) => setState(() => _binSize = v),
                  onBags: (v) => setState(() => _extraBags = v),
                  onWeight: (v) => setState(() => _weightKg = v),
                  onAddPhoto: _pickBulkyPhoto,
                  onRemovePhoto: (i) => setState(() => _bulkyPhotos.removeAt(i)),
                ),
                _Step3(
                  isImmediate: _isImmediate,
                  scheduledDate: _scheduledDate,
                  timePref: _timePref,
                  frequency: _frequency,
                  onMode: (v) => setState(() => _isImmediate = v),
                  onDate: (v) => setState(() => _scheduledDate = v),
                  onTime: (v) => setState(() => _timePref = v),
                  onFreq: (v) => setState(() => _frequency = v),
                ),
                _Step4(
                  addrCtrl: _addrCtrl,
                  notesCtrl: _notesCtrl,
                  lat: _lat,
                  lng: _lng,
                  loading: _locLoading,
                  onUseGps: _reverseGeocode,
                ),
                _Step5(
                  category: _category,
                  bulkyPhotoCount: _bulkyPhotos.length,
                  binSize: _binSize,
                  extraBags: _extraBags,
                  isImmediate: _isImmediate,
                  scheduledDate: _scheduledDate,
                  timePref: _timePref,
                  address: _addrCtrl.text,
                  base: _base,
                  bagsTotal: _bagsTotal,
                  serviceFee: _kServiceFee,
                  total: _total,
                  payment: _payment,
                  onPayment: (v) => setState(() => _payment = v),
                  error: _error,
                  promoCtrl: _promoCtrl,
                  promoDiscount: _promoDiscount,
                  promoChecking: _promoChecking,
                  onApplyPromo: _applyPromo,
                ),
              ],
            ),
          ),
          _BookFooter(
            step: _step,
            loading: _loading,
            canNext: _canNext,
            onBack: _goBack,
            onNext: _goNext,
          ),
        ]),
      ),
    );
  }
}

// ─── Step Progress Bar ────────────────────────────────────────────────────────

class _StepBar extends StatelessWidget {
  const _StepBar({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        children: List.generate(5, (i) {
          final done = i < step;
          final active = i == step;
          return [
            AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done || active ? HouseholdColors.primary : HouseholdColors.card,
                border: Border.all(
                  color: done || active ? HouseholdColors.primary : HouseholdColors.border,
                  width: 1.5,
                ),
              ),
              child: Center(
                child: done
                    ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                    : Text(
                        '${i + 1}',
                        style: HouseholdType.caption.copyWith(
                          color: active ? Colors.white : HouseholdColors.gray,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
            if (i < 4)
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  height: 2,
                  color: i < step ? HouseholdColors.primary : HouseholdColors.border,
                ),
              ),
          ];
        }).expand((e) => e).toList(),
      ),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _BookHeader extends StatelessWidget {
  const _BookHeader({required this.step, required this.onClose});
  final int step;
  final VoidCallback onClose;

  static const _titles = ['Waste Type', 'Volume', 'Schedule', 'Address', 'Review & Pay'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 20, 0),
      child: Row(children: [
        IconButton(
          onPressed: onClose,
          icon: Icon(step == 0 ? PhosphorIcons.x() : PhosphorIcons.caretLeft(), size: 22, color: HouseholdColors.forest),
        ),
        Expanded(child: Text(_titles[step], style: HouseholdType.section, textAlign: TextAlign.center)),
        Text('${step + 1} / 5', style: HouseholdType.caption.copyWith(color: HouseholdColors.primary, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

// ─── Footer ───────────────────────────────────────────────────────────────────

class _BookFooter extends StatelessWidget {
  const _BookFooter({required this.step, required this.loading, required this.canNext, required this.onBack, required this.onNext});
  final int step;
  final bool loading;
  final bool canNext;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Row(children: [
        if (step > 0) ...[
          SizedBox(
            width: 56,
            height: 56,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: HouseholdColors.card,
                shape: BoxShape.circle,
                border: Border.all(color: HouseholdColors.border),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(28),
                  onTap: onBack,
                  child: Center(child: Icon(PhosphorIcons.caretLeft(), color: HouseholdColors.forest, size: 22)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: HButton(
            label: step == 4 ? 'Confirm Booking' : 'Continue',
            icon: step == 4 ? 'payment' : null,
            loading: loading,
            onPressed: canNext ? onNext : null,
          ),
        ),
      ]),
    );
  }
}

// ─── Step 1: Category ─────────────────────────────────────────────────────────

class _Step1 extends StatelessWidget {
  const _Step1({required this.category, required this.onChanged});
  final String category;
  final ValueChanged<String> onChanged;

  static const _cats = [
    ('HOUSEHOLD', 'Household', HouseholdAssets.householdBin),
    ('PLASTIC', 'Plastic', HouseholdAssets.plasticBin),
    ('GLASS', 'Glass', HouseholdAssets.glassBin),
    ('METAL', 'Metal / Scrap', HouseholdAssets.metalBin),
    ('ORGANIC', 'Organic', HouseholdAssets.organicBin),
    ('CONSTRUCTION', 'Construction', HouseholdAssets.constructionBin),
    ('EWASTE', 'E-Waste', HouseholdAssets.ewasteBin),
    ('BULKY', 'Bulky Items', HouseholdAssets.bulkyBin),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('What type of waste?', style: HouseholdType.title),
        const SizedBox(height: 6),
        Text('Select the primary category for this collection.', style: HouseholdType.caption),
        const SizedBox(height: 20),
        GridView.count(
          // Adapt to screen width: 2 columns on phones, 3 on wide/tablet.
          crossAxisCount: MediaQuery.sizeOf(context).width >= 600 ? 3 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.15,
          children: _cats.map((c) {
            final sel = category == c.$1;
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(c.$1);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: sel ? HouseholdColors.primary.withAlpha(22) : HouseholdColors.card,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: sel ? HouseholdColors.primary : HouseholdColors.border, width: sel ? 2 : 1),
                  boxShadow: [BoxShadow(color: HouseholdColors.forest.withAlpha(12), blurRadius: 14, offset: const Offset(0, 5))],
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Expanded(child: SvgPicture.asset(c.$3, fit: BoxFit.contain)),
                  const SizedBox(height: 8),
                  Text(c.$2, style: HouseholdType.caption.copyWith(color: sel ? HouseholdColors.primary : HouseholdColors.charcoal, fontWeight: sel ? FontWeight.w700 : FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
            );
          }).toList(),
        ),
      ]),
    );
  }
}

// ─── Step 2: Volume & Extras ──────────────────────────────────────────────────

class _Step2 extends StatelessWidget {
  const _Step2({
    required this.category,
    required this.binSize,
    required this.extraBags,
    required this.weightKg,
    required this.bulkyPhotos,
    required this.bulkyDescCtrl,
    required this.onBin,
    required this.onBags,
    required this.onWeight,
    required this.onAddPhoto,
    required this.onRemovePhoto,
  });
  final String category;
  final String binSize;
  final int extraBags;
  final double weightKg;
  final List<XFile> bulkyPhotos;
  final TextEditingController bulkyDescCtrl;
  final ValueChanged<String> onBin;
  final ValueChanged<int> onBags;
  final ValueChanged<double> onWeight;
  final ValueChanged<ImageSource> onAddPhoto;
  final ValueChanged<int> onRemovePhoto;

  static const _bins = [
    ('SMALL', 'Small', '≤120L', 40),
    ('MEDIUM', 'Medium', '180L', 50),
    ('LARGE', 'Large', '240L', 60),
  ];

  Widget _negotiatedCard() => HCard(
        color: HouseholdColors.primary.withAlpha(16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(PhosphorIcons.handshake(), color: HouseholdColors.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Price agreed on arrival', style: HouseholdType.section.copyWith(color: HouseholdColors.primary)),
            const SizedBox(height: 2),
            Text('No fixed charge — your collector will look at the load and agree a fair price with you before collecting. Pay cash or MoMo on pickup.', style: HouseholdType.caption),
          ])),
        ]),
      );

  Widget _weightSlider(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Estimated weight', style: HouseholdType.section),
        const SizedBox(height: 4),
        Text('Optional — helps match the right vehicle.', style: HouseholdType.caption),
        const SizedBox(height: 12),
        HCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('0 kg', style: HouseholdType.caption),
              Text('${weightKg.round()} kg', style: HouseholdType.number.copyWith(color: HouseholdColors.primary, fontSize: 18)),
              Text('500 kg', style: HouseholdType.caption),
            ]),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(activeTrackColor: HouseholdColors.primary, thumbColor: HouseholdColors.primary, inactiveTrackColor: HouseholdColors.border, overlayColor: HouseholdColors.primary.withAlpha(30)),
              child: Slider(value: weightKg, min: 0, max: 500, divisions: 10, onChanged: onWeight),
            ),
          ]),
        ),
      ]);

  /// Photo grid shared by all categories — required for bulky, optional
  /// elsewhere so the collector can see the rubbish before arriving when it's
  /// not in a standard bin.
  Widget _photoSection(BuildContext context, {required bool isRequired}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Photos (${bulkyPhotos.length}/8)', style: HouseholdType.section),
      const SizedBox(height: 4),
      Text(
        isRequired
            ? 'Required — show your collector what to expect.'
            : 'Optional — if your rubbish isn\'t in a standard bin, a photo helps your collector prepare.',
        style: HouseholdType.caption,
      ),
      const SizedBox(height: 12),
      _photoGrid(context),
    ]);
  }

  Widget _buildBulky(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Show us the items', style: HouseholdType.title),
        const SizedBox(height: 6),
        Text('Add photos of the bulky items (mattress, wardrobe, stove…) so your collector knows what to expect.', style: HouseholdType.caption),
        const SizedBox(height: 20),
        _photoSection(context, isRequired: true),
        const SizedBox(height: 20),
        Text('What are the items?', style: HouseholdType.section),
        const SizedBox(height: 10),
        TextField(
          controller: bulkyDescCtrl,
          maxLines: 3,
          style: HouseholdType.body,
          decoration: InputDecoration(
            hintText: 'e.g. 1 double mattress, old wardrobe, gas stove',
            filled: true,
            fillColor: HouseholdColors.card,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: HouseholdColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: HouseholdColors.border)),
          ),
        ),
        const SizedBox(height: 20),
        _negotiatedCard(),
        const SizedBox(height: 20),
        _weightSlider(context),
      ]),
    );
  }

  Widget _photoGrid(BuildContext context) {
    return GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          children: [
            for (var i = 0; i < bulkyPhotos.length; i++)
              Stack(fit: StackFit.expand, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(File(bulkyPhotos[i].path), fit: BoxFit.cover),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onRemovePhoto(i);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ]),
            if (bulkyPhotos.length < 8)
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  showModalBottomSheet(
                    context: context,
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                    builder: (ctx) => SafeArea(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        ListTile(
                          leading: Icon(PhosphorIcons.camera(), color: HouseholdColors.primary),
                          title: Text('Take photo', style: HouseholdType.body),
                          onTap: () {
                            Navigator.pop(ctx);
                            onAddPhoto(ImageSource.camera);
                          },
                        ),
                        ListTile(
                          leading: Icon(PhosphorIcons.images(), color: HouseholdColors.primary),
                          title: Text('Choose from gallery', style: HouseholdType.body),
                          onTap: () {
                            Navigator.pop(ctx);
                            onAddPhoto(ImageSource.gallery);
                          },
                        ),
                      ]),
                    ),
                  );
                },
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: HouseholdColors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: HouseholdColors.primary.withAlpha(120), width: 1.5),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(PhosphorIcons.plusCircle(), color: HouseholdColors.primary, size: 28),
                    const SizedBox(height: 6),
                    Text('Add photo', style: HouseholdType.caption.copyWith(color: HouseholdColors.primary, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
          ],
        );
  }

  Widget _buildNegotiated(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('How it works', style: HouseholdType.title),
        const SizedBox(height: 6),
        Text('Recyclables and special waste are priced by your collector.', style: HouseholdType.caption),
        const SizedBox(height: 20),
        _negotiatedCard(),
        const SizedBox(height: 20),
        _photoSection(context, isRequired: false),
        const SizedBox(height: 20),
        _weightSlider(context),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (category == 'BULKY') return _buildBulky(context);
    if (category != 'HOUSEHOLD') return _buildNegotiated(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Volume & Extras', style: HouseholdType.title),
        const SizedBox(height: 6),
        Text('Choose your bin size and any additional bags.', style: HouseholdType.caption),
        const SizedBox(height: 20),
        Text('Bin size', style: HouseholdType.section),
        const SizedBox(height: 12),
        Row(
          children: _bins.map((b) {
            final sel = binSize == b.$1;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: b.$1 == 'LARGE' ? 0 : 10),
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onBin(b.$1);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: sel ? HouseholdColors.primary : HouseholdColors.card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: sel ? HouseholdColors.primary : HouseholdColors.border),
                      boxShadow: [BoxShadow(color: HouseholdColors.forest.withAlpha(12), blurRadius: 14, offset: const Offset(0, 5))],
                    ),
                    child: Column(children: [
                      Icon(PhosphorIcons.trashSimple(), size: 26, color: sel ? Colors.white : HouseholdColors.primary),
                      const SizedBox(height: 8),
                      Text(b.$2, style: HouseholdType.section.copyWith(color: sel ? Colors.white : HouseholdColors.charcoal, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(b.$3, style: HouseholdType.caption.copyWith(color: sel ? Colors.white.withAlpha(180) : HouseholdColors.gray)),
                      const SizedBox(height: 6),
                      Text('GHS ${b.$4}', style: HouseholdType.number.copyWith(color: sel ? Colors.white : HouseholdColors.primary, fontSize: 14)),
                    ]),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
        Text('Extra bags', style: HouseholdType.section),
        const SizedBox(height: 4),
        Text('GHS 16.00 each — for overflow beyond your bin.', style: HouseholdType.caption),
        const SizedBox(height: 12),
        HCard(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Extra bags', style: HouseholdType.section),
                Text(extraBags == 0 ? 'None added' : '+GHS ${(extraBags * 16).toStringAsFixed(2)}', style: HouseholdType.caption),
              ]),
            ),
            _Counter(value: extraBags, min: 0, max: 10, onChanged: onBags),
          ]),
        ),
        const SizedBox(height: 24),
        _photoSection(context, isRequired: false),
        const SizedBox(height: 24),
        _weightSlider(context),
      ]),
    );
  }
}

// ─── Step 3: Schedule ─────────────────────────────────────────────────────────

class _Step3 extends StatelessWidget {
  const _Step3({
    required this.isImmediate,
    required this.scheduledDate,
    required this.timePref,
    required this.frequency,
    required this.onMode,
    required this.onDate,
    required this.onTime,
    required this.onFreq,
  });
  final bool isImmediate;
  final DateTime? scheduledDate;
  final String timePref;
  final String frequency;
  final ValueChanged<bool> onMode;
  final ValueChanged<DateTime> onDate;
  final ValueChanged<String> onTime;
  final ValueChanged<String> onFreq;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final dates = List.generate(14, (i) => today.add(Duration(days: i + 1)));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('When should we collect?', style: HouseholdType.title),
        const SizedBox(height: 6),
        Text('Request now or schedule up to 14 days ahead.', style: HouseholdType.caption),
        const SizedBox(height: 20),
        HCard(
          padding: const EdgeInsets.all(6),
          child: Row(children: [
            Expanded(child: _ModeTab(label: 'Now', active: isImmediate, onTap: () => onMode(true))),
            Expanded(child: _ModeTab(label: 'Schedule', active: !isImmediate, onTap: () => onMode(false))),
          ]),
        ),
        if (isImmediate) ...[
          const SizedBox(height: 20),
          HCard(
            color: HouseholdColors.primary.withAlpha(16),
            child: Row(children: [
              Icon(PhosphorIcons.lightning(), color: HouseholdColors.primary, size: 22),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Immediate pickup', style: HouseholdType.section.copyWith(color: HouseholdColors.primary)),
                const SizedBox(height: 2),
                Text('A collector arrives in approximately 15–25 minutes.', style: HouseholdType.caption),
              ])),
            ]),
          ),
        ] else ...[
          const SizedBox(height: 20),
          Text('Select a date', style: HouseholdType.section),
          const SizedBox(height: 10),
          SizedBox(
            height: 88,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: dates.length,
              itemBuilder: (_, i) {
                final d = dates[i];
                final sel = scheduledDate != null && scheduledDate!.year == d.year && scheduledDate!.month == d.month && scheduledDate!.day == d.day;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onDate(d);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 66,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: sel ? HouseholdColors.primary : HouseholdColors.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: sel ? HouseholdColors.primary : HouseholdColors.border),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(DateFormat('EEE').format(d), style: HouseholdType.caption.copyWith(color: sel ? Colors.white.withAlpha(180) : HouseholdColors.gray, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('${d.day}', style: HouseholdType.section.copyWith(color: sel ? Colors.white : HouseholdColors.charcoal, fontSize: 20)),
                      const SizedBox(height: 2),
                      Text(DateFormat('MMM').format(d), style: HouseholdType.caption.copyWith(color: sel ? Colors.white.withAlpha(180) : HouseholdColors.gray)),
                    ]),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          Text('Preferred time', style: HouseholdType.section),
          const SizedBox(height: 10),
          Row(children: [
            for (final t in [('MORNING', 'Morning', '7–11am'), ('AFTERNOON', 'Afternoon', '12–4pm'), ('EVENING', 'Evening', '4–7pm')])
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: t.$1 == 'EVENING' ? 0 : 8),
                  child: _TimeChip(id: t.$1, label: t.$2, sub: t.$3, selected: timePref == t.$1, onTap: () => onTime(t.$1)),
                ),
              ),
          ]),
          const SizedBox(height: 20),
          Text('Frequency', style: HouseholdType.section),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in [('ONE_TIME', 'One-time'), ('WEEKLY', 'Weekly'), ('BIWEEKLY', 'Biweekly'), ('MONTHLY', 'Monthly')])
                _FreqChip(id: f.$1, label: f.$2, selected: frequency == f.$1, onTap: () => onFreq(f.$1)),
            ],
          ),
        ],
        const SizedBox(height: 20),
        HCard(
          color: HouseholdColors.infoTint,
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(PhosphorIcons.info(), size: 18, color: HouseholdColors.primary),
            const SizedBox(width: 10),
            Expanded(child: Text('Pickups are matched to the nearest available collector. You\'ll receive a notification when a collector is assigned.', style: HouseholdType.caption.copyWith(color: HouseholdColors.charcoal))),
          ]),
        ),
      ]),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active ? HouseholdColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(child: Text(label, style: HouseholdType.section.copyWith(color: active ? Colors.white : HouseholdColors.gray, fontSize: 15))),
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.id, required this.label, required this.sub, required this.selected, required this.onTap});
  final String id;
  final String label;
  final String sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? HouseholdColors.primary : HouseholdColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? HouseholdColors.primary : HouseholdColors.border),
        ),
        child: Column(children: [
          Text(label, style: HouseholdType.caption.copyWith(color: selected ? Colors.white : HouseholdColors.charcoal, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(sub, style: HouseholdType.caption.copyWith(color: selected ? Colors.white.withAlpha(180) : HouseholdColors.gray, fontSize: 10)),
        ]),
      ),
    );
  }
}

class _FreqChip extends StatelessWidget {
  const _FreqChip({required this.id, required this.label, required this.selected, required this.onTap});
  final String id;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? HouseholdColors.primary : HouseholdColors.card,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: selected ? HouseholdColors.primary : HouseholdColors.border),
        ),
        child: Text(label, style: HouseholdType.caption.copyWith(color: selected ? Colors.white : HouseholdColors.charcoal, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
      ),
    );
  }
}

// ─── Step 4: Address ──────────────────────────────────────────────────────────

class _Step4 extends StatelessWidget {
  const _Step4({required this.addrCtrl, required this.notesCtrl, required this.lat, required this.lng, required this.loading, required this.onUseGps});
  final TextEditingController addrCtrl;
  final TextEditingController notesCtrl;
  final double? lat;
  final double? lng;
  final bool loading;
  final VoidCallback onUseGps;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Pickup address', style: HouseholdType.title),
        const SizedBox(height: 6),
        Text('Confirm where our collector should come to.', style: HouseholdType.caption),
        const SizedBox(height: 20),
        HCard(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(children: [
            Icon(PhosphorIcons.mapPin(), color: HouseholdColors.primary, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('GPS coordinates', style: HouseholdType.caption.copyWith(color: HouseholdColors.primary, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  lat == null ? 'Acquiring location...' : '${lat!.toStringAsFixed(5)}, ${lng!.toStringAsFixed(5)}',
                  style: HouseholdType.number.copyWith(fontSize: 12, color: lat == null ? HouseholdColors.gray : HouseholdColors.charcoal),
                ),
              ]),
            ),
            if (loading)
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            else
              GestureDetector(
                onTap: onUseGps,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: HouseholdColors.primary.withAlpha(20), borderRadius: BorderRadius.circular(12)),
                  child: Text('Refresh', style: HouseholdType.caption.copyWith(color: HouseholdColors.primary, fontWeight: FontWeight.w700)),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 14),
        HTextField(
          controller: addrCtrl,
          label: 'Street address',
          hint: 'e.g. 12 Airline Road, Accra',
        ),
        const SizedBox(height: 14),
        HTextField(
          controller: notesCtrl,
          label: 'Gate / access notes (optional)',
          hint: 'e.g. Blue gate, ring bell on arrival',
        ),
        const SizedBox(height: 20),
        if (lat != null && lng != null)
          HCard(
            padding: const EdgeInsets.all(0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                height: 160,
                color: const Color(0xFF1A2535),
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(PhosphorIcons.mapPinArea(), color: HouseholdColors.primary, size: 36),
                    const SizedBox(height: 8),
                    Text('Pickup location locked', style: HouseholdType.caption.copyWith(color: HouseholdColors.card, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('${lat!.toStringAsFixed(4)}, ${lng!.toStringAsFixed(4)}', style: HouseholdType.number.copyWith(color: Colors.white.withAlpha(160), fontSize: 11)),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

// ─── Step 5: Review & Pay ─────────────────────────────────────────────────────

class _Step5 extends StatelessWidget {
  const _Step5({
    required this.category,
    required this.bulkyPhotoCount,
    required this.binSize,
    required this.extraBags,
    required this.isImmediate,
    required this.scheduledDate,
    required this.timePref,
    required this.address,
    required this.base,
    required this.bagsTotal,
    required this.serviceFee,
    required this.total,
    required this.payment,
    required this.onPayment,
    required this.promoCtrl,
    required this.promoDiscount,
    required this.promoChecking,
    required this.onApplyPromo,
    this.error,
  });
  final String category;
  final int bulkyPhotoCount;
  final String binSize;
  final int extraBags;
  final bool isImmediate;
  final DateTime? scheduledDate;
  final String timePref;
  final String address;
  final double base;
  final double bagsTotal;
  final double serviceFee;
  final double total;
  final String payment;
  final ValueChanged<String> onPayment;
  final TextEditingController promoCtrl;
  final double promoDiscount;
  final bool promoChecking;
  final VoidCallback onApplyPromo;
  final String? error;

  static String _catLabel(String c) {
    const m = {'HOUSEHOLD': 'Household', 'PLASTIC': 'Plastic', 'GLASS': 'Glass', 'METAL': 'Metal / Scrap', 'ORGANIC': 'Organic', 'CONSTRUCTION': 'Construction', 'EWASTE': 'E-Waste', 'BULKY': 'Bulky Items'};
    return m[c] ?? c;
  }

  bool get _fixed => category == 'HOUSEHOLD';

  static String _binLabel(String b) => b[0] + b.substring(1).toLowerCase();

  static String _timeLabel(String t) {
    const m = {'MORNING': 'Morning (7–11am)', 'AFTERNOON': 'Afternoon (12–4pm)', 'EVENING': 'Evening (4–7pm)'};
    return m[t] ?? t;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_fixed ? 'Review & pay' : 'Review & confirm', style: HouseholdType.title),
        const SizedBox(height: 6),
        Text(_fixed ? 'Confirm your booking details before payment.' : 'Confirm your booking details.', style: HouseholdType.caption),
        const SizedBox(height: 18),
        HCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Booking summary', style: HouseholdType.section),
            const SizedBox(height: 14),
            _ReviewRow(label: 'Category', value: _catLabel(category)),
            if (_fixed) _ReviewRow(label: 'Bin size', value: '${_binLabel(binSize)} — GHS ${base.toStringAsFixed(2)}'),
            if (_fixed && extraBags > 0) _ReviewRow(label: 'Extra bags', value: '$extraBags × GHS 16.00'),
            if (bulkyPhotoCount > 0) _ReviewRow(label: 'Photos', value: '$bulkyPhotoCount photo${bulkyPhotoCount == 1 ? '' : 's'} attached'),
            _ReviewRow(label: 'Schedule', value: isImmediate ? 'Immediate pickup' : scheduledDate != null ? '${DateFormat('EEE d MMM').format(scheduledDate!)} · ${_timeLabel(timePref)}' : 'Not set'),
            _ReviewRow(label: 'Address', value: address.isEmpty ? 'Not entered' : address, multiLine: true),
          ]),
        ),
        const SizedBox(height: 14),
        if (!_fixed) ...[
          HCard(
            color: HouseholdColors.primary.withAlpha(16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(PhosphorIcons.handshake(), color: HouseholdColors.primary, size: 22),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Price agreed on arrival', style: HouseholdType.section.copyWith(color: HouseholdColors.primary)),
                const SizedBox(height: 2),
                Text('Your collector will agree a fair price with you before collecting. Pay them directly — cash or MoMo — on pickup.', style: HouseholdType.caption),
              ])),
            ]),
          ),
        ] else ...[
        HCard(
          child: Column(children: [
            _PriceRow(label: 'Collection fee', amount: base),
            if (extraBags > 0) _PriceRow(label: 'Extra bags ($extraBags)', amount: bagsTotal),
            _PriceRow(label: 'Service fee', amount: serviceFee),
            if (promoDiscount > 0)
              _PriceRow(label: 'Promo discount', amount: -promoDiscount),
            Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1, color: HouseholdColors.border)),
            Row(children: [
              Expanded(child: Text('Total', style: HouseholdType.section)),
              Text('GHS ${total.toStringAsFixed(2)}', style: HouseholdType.number.copyWith(color: HouseholdColors.primary, fontSize: 20, fontWeight: FontWeight.w700)),
            ]),
          ]),
        ),
        const SizedBox(height: 14),
        // Promo code
        Row(children: [
          Expanded(child: TextField(
            controller: promoCtrl,
            textCapitalization: TextCapitalization.characters,
            style: HouseholdType.body,
            decoration: InputDecoration(
              hintText: 'Promo code',
              prefixIcon: const Icon(Icons.local_offer_outlined, size: 18),
              filled: true,
              fillColor: HouseholdColors.card,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: HouseholdColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: HouseholdColors.border)),
            ),
          )),
          const SizedBox(width: 10),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: promoChecking ? null : onApplyPromo,
              style: FilledButton.styleFrom(backgroundColor: HouseholdColors.charcoal),
              child: promoChecking
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Apply'),
            ),
          ),
        ]),
        const SizedBox(height: 18),
        Text('Payment method', style: HouseholdType.section),
        const SizedBox(height: 12),
        for (final m in [
          ('CASH', 'Cash on pickup', PhosphorIcons.money()),
          ('MTN_MOMO', 'MTN MoMo', PhosphorIcons.deviceMobile()),
          ('TELECEL', 'Telecel Cash', PhosphorIcons.deviceMobile()),
          ('AIRTELTIGO', 'AirtelTigo', PhosphorIcons.deviceMobile()),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onPayment(m.$1);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: payment == m.$1 ? HouseholdColors.primary.withAlpha(18) : HouseholdColors.card,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: payment == m.$1 ? HouseholdColors.primary : HouseholdColors.border, width: payment == m.$1 ? 2 : 1),
                  boxShadow: [BoxShadow(color: HouseholdColors.forest.withAlpha(10), blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: Row(children: [
                  Icon(m.$3, color: payment == m.$1 ? HouseholdColors.primary : HouseholdColors.gray, size: 22),
                  const SizedBox(width: 14),
                  Expanded(child: Text(m.$2, style: HouseholdType.section.copyWith(color: payment == m.$1 ? HouseholdColors.primary : HouseholdColors.charcoal))),
                  if (payment == m.$1) Icon(PhosphorIcons.checkCircle(PhosphorIconsStyle.fill), color: HouseholdColors.primary, size: 22),
                ]),
              ),
            ),
          ),
        if (payment != 'CASH') ...[
          const SizedBox(height: 4),
          HCard(
            color: HouseholdColors.infoTint,
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(PhosphorIcons.info(), color: HouseholdColors.primary, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text('You\'ll receive a mobile money prompt to approve the payment after confirming.', style: HouseholdType.caption.copyWith(color: HouseholdColors.charcoal))),
            ]),
          ),
        ],
        ],
        if (error != null) ...[
          const SizedBox(height: 12),
          HCard(
            color: HouseholdColors.dangerTint,
            child: Row(children: [
              Icon(PhosphorIcons.warning(), color: HouseholdColors.danger, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(error!, style: HouseholdType.caption.copyWith(color: HouseholdColors.danger, fontWeight: FontWeight.w600))),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.value, this.multiLine = false});
  final String label;
  final String value;
  final bool multiLine;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: multiLine ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SizedBox(width: 90, child: Text(label, style: HouseholdType.caption)),
          Expanded(child: Text(value, style: HouseholdType.body.copyWith(fontWeight: FontWeight.w600, fontSize: 13), maxLines: multiLine ? 3 : 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({required this.label, required this.amount});
  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(child: Text(label, style: HouseholdType.body.copyWith(color: HouseholdColors.gray))),
        Text('GHS ${amount.toStringAsFixed(2)}', style: HouseholdType.number.copyWith(fontSize: 14)),
      ]),
    );
  }
}

// ─── Counter ──────────────────────────────────────────────────────────────────

class _Counter extends StatelessWidget {
  const _Counter({required this.value, required this.min, required this.max, required this.onChanged});
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _CBtn(icon: PhosphorIcons.minus(), enabled: value > min, onTap: () { HapticFeedback.selectionClick(); onChanged(value - 1); }),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text('$value', style: HouseholdType.number.copyWith(fontSize: 22, color: HouseholdColors.charcoal)),
      ),
      _CBtn(icon: PhosphorIcons.plus(), enabled: value < max, onTap: () { HapticFeedback.selectionClick(); onChanged(value + 1); }),
    ]);
  }
}

class _CBtn extends StatelessWidget {
  const _CBtn({required this.icon, required this.enabled, required this.onTap});
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : 0.35,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 38, height: 38,
          decoration: BoxDecoration(shape: BoxShape.circle, color: HouseholdColors.primary.withAlpha(20), border: Border.all(color: HouseholdColors.primary.withAlpha(60))),
          child: Icon(icon, size: 17, color: HouseholdColors.primary),
        ),
      ),
    );
  }
}
