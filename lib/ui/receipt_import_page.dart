import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../data/db.dart';
import '../data/providers.dart';
import '../models/models.dart';
import '../parsing/merchant.dart';
import '../services/openrouter.dart';
import '../services/receipt_import.dart';
import '../services/settings_service.dart';
import 'settings_page.dart';
import 'transaction_edit_page.dart';

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
final _dateFmt = DateFormat('d MMM, h:mm a');

/// Reads a payment receipt and hands what it says to the transaction form.
///
/// Some banks never send an SMS for small UPI debits, so the screenshot the
/// payment app offers to share is the only record there is. This takes that
/// image — shared in from the payment app, or picked here — and fills the
/// form from it.
///
/// The image stays on screen while it is read, so there is never any doubt
/// about which receipt the numbers came from.
class ReceiptImportPage extends ConsumerStatefulWidget {
  /// An image shared in from another app, already decoded.
  final Uint8List? image;

  /// Where to get the image from instead, when none was shared.
  final ImageSource? source;

  const ReceiptImportPage({super.key, this.image, this.source})
      : assert(image != null || source != null,
            'Give the page an image or somewhere to get one');

  @override
  ConsumerState<ReceiptImportPage> createState() => _ReceiptImportPageState();
}

class _ReceiptImportPageState extends ConsumerState<ReceiptImportPage> {
  Uint8List? _image;
  bool _reading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _image = widget.image;
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (_image == null) {
      // Downscaled before it ever leaves the device: a receipt reads fine
      // at this size, and a full-resolution screenshot would cost several
      // times as much to send.
      final picked = await ImagePicker().pickImage(
        source: widget.source!,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 85,
      );
      if (!mounted) return;
      if (picked == null) {
        Navigator.pop(context);
        return;
      }
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() => _image = bytes);
    }
    await _read();
  }

  Future<void> _read() async {
    final image = _image;
    if (image == null) return;
    setState(() {
      _reading = true;
      _error = null;
    });

    ReceiptReading? reading;
    String? error;
    try {
      reading = await ref.read(receiptImportProvider).read(image);
    } on OpenRouterException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Could not read the receipt: $e';
    }
    if (!mounted) return;

    if (reading == null) {
      setState(() {
        _reading = false;
        _error = error;
      });
      return;
    }

    final draft = _draft(reading);

    // The SMS for this payment may have landed after all, or the receipt
    // may have been shared twice. Either way, recording it again would
    // double the month's spend.
    final existing = await ref.read(dbProvider).findReceiptDuplicate(
          amount: draft.amount,
          at: draft.occurredAt,
          reference: reading.reference,
        );
    if (!mounted) return;
    if (existing != null && !await _confirmDuplicate(existing)) {
      if (mounted) Navigator.pop(context);
      return;
    }
    if (!mounted) return;

    // Straight to the form rather than another confirmation step: the
    // receipt was shared on purpose, and the form is where a wrong reading
    // gets corrected anyway.
    await Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute(builder: (_) => TransactionEditPage(prefill: draft)),
    );
  }

  Future<bool> _confirmDuplicate(Transaction existing) async {
    final what = [
      _rupee.format(existing.amount),
      if (existing.merchant != null) 'to ${existing.merchant}',
      'on ${_dateFmt.format(existing.occurredAt)}',
    ].join(' ');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Already recorded?'),
        content: Text('There is already a transaction for $what. Adding '
            'this receipt as well would count the payment twice.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('NEVER MIND'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ADD ANYWAY'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Transaction _draft(ReceiptReading r) {
    // The reference is what lets this be matched against a bank statement
    // later, so it is kept rather than dropped.
    final note = [
      if (r.reference != null) 'UPI ref ${r.reference}',
      ?r.note,
    ].join(' · ');

    return Transaction(
      id: 0,
      amount: r.amount,
      type: r.type,
      // A UPI payment comes off a bank account unless the receipt names a
      // card, which they generally do not.
      accountKind: AccountKind.bank,
      accountTail: r.accountTail,
      merchant: MerchantName.display(r.merchant),
      bank: r.bank,
      note: note.isEmpty ? null : note,
      source: 'receipt',
      // A receipt with no date on it is dated now, which is when it was
      // shared, and is as close as anything available.
      occurredAt: r.occurredAt ?? DateTime.now(),
      createdAt: DateTime.now(),
      synced: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return Scaffold(
      appBar: AppBar(title: const Text('Payment receipt')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (image != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                image,
                height: 320,
                width: double.infinity,
                fit: BoxFit.contain,
              ),
            ),
          const SizedBox(height: 24),
          if (_reading)
            const Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Reading the payment off this receipt...'),
              ],
            )
          else if (_error != null)
            _Error(message: _error!, onRetry: _read),
        ],
      ),
    );
  }
}

class _Error extends ConsumerWidget {
  final String message;
  final VoidCallback onRetry;
  const _Error({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configured = ref.read(receiptImportProvider).isConfigured;
    final acceptsImages = ref.watch(settingsProvider).modelAcceptsImages;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline,
                color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        if (acceptsImages == false)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'The model you picked cannot read images. Choose one marked '
              'with a camera in Settings.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
            if (!configured || acceptsImages == false)
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                ),
                child: const Text('Settings'),
              ),
            TextButton(
              onPressed: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => const TransactionEditPage(),
                ),
              ),
              child: const Text('Enter by hand'),
            ),
          ],
        ),
      ],
    );
  }
}
