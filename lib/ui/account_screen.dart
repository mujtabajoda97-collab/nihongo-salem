import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/cloud.dart';
import '../services/cloud_sync.dart';
import 'theme.dart';

/// Create an account or sign in, so progress is saved in the cloud.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _leave() => context.canPop() ? context.pop() : context.go('/');

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'اكتب بريداً إلكترونياً صحيحاً');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'كلمة المرور 6 أحرف على الأقل');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final sync = ref.read(cloudSyncProvider.notifier);
    try {
      if (_register) {
        await sync.signUp(email, password);
      } else {
        await sync.signIn(email, password);
      }
      if (mounted) _leave();
    } on CloudException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.messageAr;
          // Account created but needs the email link: switch to the sign-in form.
          if (e.needsEmailConfirmation) _register = false;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_register ? 'إنشاء حساب' : 'تسجيل الدخول')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            const SizedBox(height: 12),
            Container(
              width: 84,
              height: 84,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.premium.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cloud_sync_rounded, size: 44, color: AppColors.premium),
            ),
            const SizedBox(height: 16),
            Text('احفظ تقدّمك للأبد',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              'نجومك وحلقاتك ومسار الحروف تُحفظ في حسابك، فلا تضيع إذا حذفت التطبيق أو فتحته من جهاز آخر.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.muted, height: 1.7),
            ),
            const SizedBox(height: 24),
            Directionality(
              textDirection: TextDirection.ltr,
              child: TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.mail_outline_rounded),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Directionality(
              textDirection: TextDirection.ltr,
              child: TextField(
                controller: _password,
                obscureText: _hidePassword,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => _busy ? null : _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(_hidePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _hidePassword = !_hidePassword),
                  ),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE3E6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(_error!, style: const TextStyle(color: AppColors.brand)),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : Text(_register ? 'إنشاء الحساب' : 'دخول'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _register = !_register;
                        _error = null;
                      }),
              child: Text(_register ? 'لديّ حساب، أريد تسجيل الدخول' : 'ليس لديّ حساب، أنشئ حساباً جديداً'),
            ),
            TextButton(
              onPressed: _busy ? null : _leave,
              child: const Text('متابعة بدون حساب'),
            ),
          ],
        ),
      ),
    );
  }
}
