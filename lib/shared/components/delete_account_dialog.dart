import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../../features/auth/providers/auth_provider.dart';

/// Asks the person to type DELETE, deletes the account and returns to login.
Future<void> confirmAndDeleteAccount(BuildContext context) async {
  final controller = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Delete your account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This permanently removes your sign-in, name, phone number, email, '
              'photo and saved addresses. Records of past pickups and payments '
              'are kept without your personal details. This cannot be undone.',
            ),
            const SizedBox(height: 16),
            const Text('Type DELETE to confirm'),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: controller.text.trim().toUpperCase() == 'DELETE'
                ? () => Navigator.pop(ctx, true)
                : null,
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete account'),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  if (confirmed != true || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  try {
    await context.read<AuthProvider>().deleteAccount();
    navigator.pushNamedAndRemoveUntil('/login', (_) => false);
    messenger.showSnackBar(
      const SnackBar(content: Text('Your account has been deleted.')),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text(ApiClient.messageFrom(e) ??
          'Could not delete your account. Check your connection and try again.'),
    ));
  }
}
