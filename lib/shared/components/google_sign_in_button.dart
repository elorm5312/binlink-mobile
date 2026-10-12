import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Official four-colour Google "G" (Google Sign-In branding guidelines).
const _googleG = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
<path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/>
<path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/>
<path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/>
<path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/>
</svg>''';

/// "Continue with Google" in Google's light (white) or dark (#131314) style.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.onPressed,
    this.dark = false,
    this.loading = false,
    this.label = 'Continue with Google',
  });

  final VoidCallback? onPressed;
  final bool dark;
  final bool loading;
  final String label;

  @override
  Widget build(BuildContext context) {
    final bg = dark ? const Color(0xFF131314) : Colors.white;
    final fg = dark ? const Color(0xFFE3E3E3) : const Color(0xFF1F1F1F);
    final border = dark ? const Color(0xFF8E918F) : const Color(0xFF747775);
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton(
        onPressed: loading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: bg,
          disabledBackgroundColor: bg,
          foregroundColor: fg,
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
            else
              SvgPicture.string(_googleG, width: 20, height: 20),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'PlusJakartaSans',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
