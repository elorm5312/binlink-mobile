import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../../core/design_system/collector_design_system.dart';
import '../../../core/services/maps_launcher.dart';
import '../../../shared/components/binlink_map.dart';
import '../../../shared/screens/chat_screen.dart';
import '../providers/collector_provider.dart';
import 'navigation_screen.dart';

class ActivePickupScreen extends StatefulWidget {
  const ActivePickupScreen({super.key, this.booking = const {}});
  final Map<String, dynamic> booking;

  @override
  State<ActivePickupScreen> createState() => _ActivePickupScreenState();
}

class _ActivePickupScreenState extends State<ActivePickupScreen> {
  late String _status = widget.booking['status'] as String? ?? 'ACCEPTED';
  double _weight = 18;
  final _picker = ImagePicker();
  final Set<String> _uploadedPhotos = {};
  String? _photoError;
  bool _photoLoading = false;
  bool _reportingException = false;

  bool get _isNegotiated => widget.booking['pricingMode'] == 'NEGOTIATED';

  /// All photos the household attached to the request (bulky-item photos and/or
  /// a general waste photo), so the collector can see the load before arriving.
  List<String> get _customerPhotos {
    final list = ((widget.booking['bulkyPhotos'] as List?) ?? const [])
        .whereType<String>()
        .toList();
    final waste = widget.booking['wastePhotoUrl'] as String?;
    if (waste != null && waste.isNotEmpty && !list.contains(waste)) list.add(waste);
    return list;
  }

  bool get _enRoute => const ['ACCEPTED', 'ASSIGNED', 'ON_THE_WAY', 'EN_ROUTE'].contains(_status);

  void _viewPhoto(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: InteractiveViewer(
          child: Image.network(url,
              errorBuilder: (_, __, ___) => Container(
                  height: 200, color: CollectorColors.charcoal,
                  child: Icon(PhosphorIcons.imageBroken(), color: CollectorColors.white))),
        ),
      ),
    );
  }

  /// Opens external Google Maps turn-by-turn navigation to the pickup.
  Future<void> _launchNavigation() async {
    final lat = (widget.booking['pickupLat'] as num?)?.toDouble();
    final lng = (widget.booking['pickupLng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;
    final ok = await MapsLauncher.navigateTo(lat, lng,
        label: widget.booking['pickupAddress'] as String?);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Google Maps. Is it installed?')),
      );
    }
  }

  /// Asks the collector for the price agreed with the household. Returns null
  /// if cancelled.
  Future<double?> _askAgreedPrice() async {
    final ctrl = TextEditingController();
    String? fieldError;
    return showDialog<double>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setDialogState) => AlertDialog(
          backgroundColor: CollectorColors.charcoal,
          title: Text('Agreed price', style: CollectorType.title),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Enter the amount (GHS) you agreed with the customer for this pickup.',
                style: CollectorType.caption),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: CollectorType.title,
              decoration: InputDecoration(
                prefixText: 'GHS ',
                prefixStyle: CollectorType.title,
                hintText: '0.00',
                errorText: fieldError,
                filled: true,
                fillColor: CollectorColors.dark,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: CollectorColors.green),
              onPressed: () {
                final v = double.tryParse(ctrl.text.trim());
                if (v == null || v <= 0) {
                  setDialogState(() => fieldError = 'Enter a valid amount');
                  return;
                }
                Navigator.pop(d, v);
              },
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
  }

  void _openChat() {
    final bookingId = widget.booking['id'] as String?;
    if (bookingId == null) return;
    final household = widget.booking['household'] as Map<String, dynamic>?;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(
        bookingId: bookingId,
        peerName: household?['fullName'] as String? ?? 'Customer',
      ),
    ));
  }

  Future<void> _confirmNoShow(CollectorProvider provider) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: CollectorColors.charcoal,
        title: Text('Report no-show?', style: CollectorType.title),
        content: Text('Confirm the customer was not available. They will be charged a no-show fee and you\'ll be compensated.',
            style: CollectorType.caption),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: CollectorColors.warning),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Report'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final bookingId = widget.booking['id'] as String?;
    if (bookingId == null) return;
    final ok = await provider.reportNoShow(bookingId);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(ok ? 'No-show reported. You\'ve been compensated.' : 'Could not report no-show.')));
    if (ok) navigator.maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final lat = (widget.booking['pickupLat'] as num?)?.toDouble();
    final lng = (widget.booking['pickupLng'] as num?)?.toDouble();
    final provider = context.read<CollectorProvider>();
    return Scaffold(
      backgroundColor: CollectorColors.dark,
      body: Stack(children: [
        if (lat != null && lng != null)
          Positioned.fill(child: BinLinkMap(initialPosition: ll.LatLng(lat, lng), pickupPosition: ll.LatLng(lat, lng), isNavigating: true))
        else
          Positioned.fill(
            child: Center(
              child: CPanel(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SvgPicture.asset('assets/collector_assets/errors/location_permission.svg', height: 180),
                  const SizedBox(height: 12),
                  Text('Route unavailable', style: CollectorType.title),
                  const SizedBox(height: 8),
                  Text('Pickup coordinates are missing for this job.', textAlign: TextAlign.center, style: CollectorType.caption),
                ]),
              ),
            ),
          ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 14,
          left: 16,
          right: 16,
          child: CPanel(child: Row(children: [
            IconButton(onPressed: () => Navigator.maybePop(context), icon: CIcon('route', color: CollectorColors.white)),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_status.replaceAll('_', ' '), style: CollectorType.title),
              Text(widget.booking['pickupAddress'] as String? ?? 'Active pickup route', maxLines: 1, overflow: TextOverflow.ellipsis, style: CollectorType.caption),
            ])),
            IconButton(
              onPressed: () {
                final plat = (widget.booking['pickupLat'] as num?)?.toDouble();
                final plng = (widget.booking['pickupLng'] as num?)?.toDouble();
                if (plat == null || plng == null) return;
                Navigator.push(context, MaterialPageRoute(builder: (_) => NavigationScreen(
                  destination: ll.LatLng(plat, plng),
                  label: widget.booking['pickupAddress'] as String? ?? 'Pickup location',
                )));
              },
              icon: Icon(PhosphorIcons.navigationArrow(), color: CollectorColors.white),
            ),
            IconButton(
              onPressed: _openChat,
              icon: Icon(PhosphorIcons.chatCircleDots(), color: CollectorColors.white),
            ),
          ])),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: CPanel(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SvgPicture.asset(_assetForStatus(_status), height: 120),
              const SizedBox(height: 10),
              Text(_etaText, style: CollectorType.hero),
              Text('Navigation, proof capture, weight and completion', style: CollectorType.caption),
              if (_isNegotiated) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: CollectorColors.green.withAlpha(28),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(PhosphorIcons.handshake(), color: CollectorColors.green, size: 16),
                    const SizedBox(width: 8),
                    Flexible(child: Text('Negotiate the price with the customer on arrival',
                        style: CollectorType.caption.copyWith(color: CollectorColors.green, fontWeight: FontWeight.w700))),
                  ]),
                ),
              ],
              if (_customerPhotos.isNotEmpty) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text("Customer's photo${_customerPhotos.length > 1 ? 's' : ''} — tap to view",
                      style: CollectorType.caption.copyWith(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 96,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _customerPhotos.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () => _viewPhoto(_customerPhotos[i]),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(_customerPhotos[i], width: 120, height: 96, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(width: 120, height: 96, color: CollectorColors.charcoal,
                                child: Icon(PhosphorIcons.imageBroken(), color: CollectorColors.white, size: 22))),
                      ),
                    ),
                  ),
                ),
              ],
              if (_photoError != null) ...[
                const SizedBox(height: 10),
                Text(_photoError!, style: CollectorType.caption.copyWith(color: CollectorColors.red)),
              ],
              const SizedBox(height: 16),
              if (_status == 'ARRIVED' || _status == 'COLLECTING') ...[
                Slider(value: _weight, min: 1, max: 120, activeColor: CollectorColors.green, onChanged: (v) => setState(() => _weight = v)),
                Text('Weight capture: ${_weight.round()} kg', style: CollectorType.caption),
                const SizedBox(height: 10),
              ],
              CButton(label: _nextLabel(_status), icon: 'navigation', onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context);
                final action = _nextAction(_status);
                final bookingId = widget.booking['id'] as String?;
                if (bookingId == null) return;
                double? agreedAmount;
                if (action == 'complete' && _isNegotiated) {
                  agreedAmount = await _askAgreedPrice();
                  if (agreedAmount == null || !mounted) return;
                }
                final ok = await provider.updateStatus(bookingId, action, actualWeightKg: _weight, agreedAmount: agreedAmount);
                if (!mounted) return;
                if (!ok) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(provider.error ?? 'Could not update status. Try again.')),
                  );
                  // Recover from a desync: adopt the server's real status.
                  final serverStatus = provider.statusForBooking(bookingId);
                  if (serverStatus != null && serverStatus != _status) {
                    setState(() => _status = serverStatus);
                  }
                  return;
                }
                final nextStatus = _nextStatus(_status);
                setState(() => _status = nextStatus);
                // Starting the trip → open Google Maps turn-by-turn.
                if (action == 'on-the-way' || action == 'en-route') {
                  await _launchNavigation();
                }
                if (nextStatus == 'COMPLETED') {
                  navigator.maybePop();
                }
              }),
              if (_enRoute) ...[
                const SizedBox(height: 10),
                CButton(label: 'OPEN GOOGLE MAPS', icon: 'navigation', secondary: true, onPressed: _launchNavigation),
              ],
              if (_status == 'ARRIVED' || _status == 'COLLECTING') ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => _confirmNoShow(provider),
                  child: Text('Customer didn\'t show up?',
                      style: CollectorType.caption.copyWith(color: CollectorColors.warning, fontWeight: FontWeight.w700)),
                ),
              ],
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: CButton(label: _uploadedPhotos.contains('BEFORE') ? 'BEFORE SAVED' : 'BEFORE PHOTO', icon: 'before_photo', secondary: true, loading: _photoLoading, onPressed: () => _capturePhoto(provider, 'BEFORE'))),
                const SizedBox(width: 10),
                Expanded(child: CButton(label: _uploadedPhotos.contains('AFTER') ? 'AFTER SAVED' : 'AFTER PHOTO', icon: 'after_photo', secondary: true, loading: _photoLoading, onPressed: () => _capturePhoto(provider, 'AFTER'))),
              ]),
              const SizedBox(height: 10),
              CButton(label: 'REPORT ISSUE', icon: 'help', secondary: true, loading: _reportingException, onPressed: () => _reportException(provider)),
            ]),
          ),
        ),
      ]),
    );
  }

  String get _etaText {
    final raw = widget.booking['etaMinutes'] ?? widget.booking['eta'] ?? widget.booking['estimatedMinutes'];
    final minutes = raw is num ? raw.round() : int.tryParse(raw?.toString() ?? '');
    if (minutes == null || minutes <= 0) return 'ETA pending';
    return '$minutes min';
  }

  Future<void> _capturePhoto(CollectorProvider provider, String type) async {
    final bookingId = widget.booking['id'] as String?;
    if (bookingId == null) {
      setState(() => _photoError = 'Cannot upload photo without a booking id.');
      return;
    }
    setState(() {
      _photoLoading = true;
      _photoError = null;
    });
    try {
      final image = await _picker.pickImage(source: ImageSource.camera, imageQuality: 82, maxWidth: 1600);
      if (image == null) return;
      final url = await provider.uploadPhoto(bookingId, type, image.path);
      if (url == null) {
        setState(() => _photoError = 'Photo upload failed. Try again with a stronger connection.');
      } else {
        setState(() => _uploadedPhotos.add(type));
      }
    } catch (_) {
      setState(() => _photoError = 'Camera or upload failed. Check permissions and retry.');
    } finally {
      if (mounted) setState(() => _photoLoading = false);
    }
  }

  String _assetForStatus(String s) {
    if (s == 'ARRIVED') return 'assets/collector_assets/workflow/arrived.svg';
    if (s == 'COLLECTING') return 'assets/collector_assets/workflow/weight_capture.svg';
    if (s == 'COLLECTED') return 'assets/collector_assets/workflow/complete_job.svg';
    return 'assets/collector_assets/workflow/navigation.svg';
  }

  String _nextLabel(String s) {
    if (s == 'ACCEPTED' || s == 'ASSIGNED') return 'START NAVIGATION';
    if (s == 'ON_THE_WAY' || s == 'EN_ROUTE') return 'MARK ARRIVED';
    if (s == 'ARRIVED') return 'START COLLECTING';
    if (s == 'COLLECTING') return 'COMPLETE WITH WEIGHT';
    return 'CLOSE JOB';
  }

  String _nextAction(String s) {
    if (s == 'ACCEPTED' || s == 'ASSIGNED') return 'on-the-way';
    if (s == 'ON_THE_WAY' || s == 'EN_ROUTE') return 'arrived';
    if (s == 'ARRIVED') return 'collecting';
    return 'complete';
  }

  String _nextStatus(String s) {
    if (s == 'ACCEPTED' || s == 'ASSIGNED') return 'ON_THE_WAY';
    if (s == 'ON_THE_WAY' || s == 'EN_ROUTE') return 'ARRIVED';
    if (s == 'ARRIVED') return 'COLLECTING';
    return 'COMPLETED';
  }

  Future<void> _reportException(CollectorProvider provider) async {
    final bookingId = widget.booking['id'] as String?;
    if (bookingId == null) {
      setState(() => _photoError = 'Cannot report an exception without a booking id.');
      return;
    }

    final note = TextEditingController();
    String reason = 'GATE_LOCKED';
    String? photoUrl;
    String? validationError;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          backgroundColor: CollectorColors.charcoal,
          title: Text('Report exception', style: CollectorType.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: reason,
                dropdownColor: CollectorColors.charcoal,
                items: const [
                  DropdownMenuItem(value: 'GATE_LOCKED', child: Text('Gate Locked')),
                  DropdownMenuItem(value: 'HAZARDOUS_WASTE', child: Text('Hazardous Waste')),
                  DropdownMenuItem(value: 'CUSTOMER_NOT_HOME', child: Text('Customer Not Home')),
                  DropdownMenuItem(value: 'OVERFILLED_LOAD', child: Text('Overfilled Load')),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => reason = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                minLines: 3,
                maxLines: 5,
                onChanged: (_) {
                  if (validationError != null && note.text.trim().isNotEmpty) {
                    setDialogState(() => validationError = null);
                  }
                },
                decoration: const InputDecoration(labelText: 'Note'),
              ),
              const SizedBox(height: 12),
              CButton(
                label: photoUrl == null ? 'CAPTURE EXCEPTION PHOTO' : 'PHOTO CAPTURED',
                icon: 'camera',
                secondary: true,
                onPressed: () async {
                  final image = await _picker.pickImage(source: ImageSource.camera, imageQuality: 82, maxWidth: 1600);
                  if (image == null) return;
                  final uploaded = await provider.uploadPhoto(bookingId, 'EXCEPTION', image.path);
                  if (uploaded != null) {
                    setDialogState(() {
                      photoUrl = uploaded;
                      validationError = null;
                    });
                  }
                },
              ),
              if (validationError != null) ...[
                const SizedBox(height: 12),
                Text(
                  validationError!,
                  style: CollectorType.caption.copyWith(color: CollectorColors.red),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                if (note.text.trim().isEmpty) {
                  setDialogState(() => validationError = 'Please enter a note.');
                  return;
                }
                if (photoUrl == null) {
                  setDialogState(() => validationError = 'Please attach a photo.');
                  return;
                }
                setDialogState(() => validationError = null);
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || photoUrl == null) return;

    setState(() {
      _reportingException = true;
      _photoError = null;
    });
    try {
      final ok = await provider.reportException(bookingId, reason, note.text.trim(), photoUrl: photoUrl);
      if (ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Exception reported to the household.')),
        );
      } else if (!ok && mounted) {
        setState(() => _photoError = 'Exception report failed. Please retry.');
      }
    } catch (_) {
      if (mounted) setState(() => _photoError = 'Exception report failed. Please retry.');
    } finally {
      if (mounted) setState(() => _reportingException = false);
    }
  }
}
