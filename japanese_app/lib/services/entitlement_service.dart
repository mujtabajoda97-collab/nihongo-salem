import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';

enum PlanPeriod { monthly, annual, other }

/// A subscription option shown on the paywall. [raw] is the store object and
/// is only read back by the service that created it.
class PaywallPlan {
  const PaywallPlan({
    required this.identifier,
    required this.title,
    required this.priceString,
    required this.period,
    required this.raw,
    this.priceAmount,
    this.currencyCode,
  });

  final String identifier;
  final String title;

  /// Already localised by the store, e.g. "9.99 $".
  final String priceString;
  final PlanPeriod period;
  final Object? raw;

  /// Numeric price, used to compute the "save x%" badge. Null if unknown.
  final double? priceAmount;
  final String? currencyCode;
}

enum PurchaseOutcome { purchased, cancelled, failed }

/// Subscription backend. The rest of the app depends only on this interface.
abstract interface class EntitlementService {
  /// Call once at launch.
  Future<void> init();

  /// Emits the new answer every time the subscription state changes
  /// (purchase, renewal, expiry, restore on another device).
  Stream<bool> get premiumChanges;

  /// Asks the store for the current answer.
  Future<bool> refresh();

  Future<List<PaywallPlan>> loadPlans();
  Future<PurchaseOutcome> purchase(PaywallPlan plan);

  /// "Restore purchases". Returns the premium state afterwards.
  Future<bool> restore();

  Future<void> dispose();
}

/// RevenueCat implementation (entitlement id: [AppRules.premiumEntitlementId]).
class RevenueCatEntitlementService implements EntitlementService {
  RevenueCatEntitlementService({required this.apiKey});

  final String apiKey;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  void Function(CustomerInfo)? _listener;

  @override
  Stream<bool> get premiumChanges => _controller.stream;

  @override
  Future<void> init() async {
    await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.warn);
    await Purchases.configure(PurchasesConfiguration(apiKey));
    _listener = (info) => _controller.add(_isPremium(info));
    Purchases.addCustomerInfoUpdateListener(_listener!);
  }

  @override
  Future<bool> refresh() async {
    final info = await Purchases.getCustomerInfo();
    return _isPremium(info);
  }

  @override
  Future<List<PaywallPlan>> loadPlans() async {
    final offerings = await Purchases.getOfferings();
    final packages = offerings.current?.availablePackages ?? const <Package>[];
    return [
      for (final p in packages)
        PaywallPlan(
          identifier: p.identifier,
          title: p.storeProduct.title,
          priceString: p.storeProduct.priceString,
          priceAmount: p.storeProduct.price,
          currencyCode: p.storeProduct.currencyCode,
          period: switch (p.packageType) {
            PackageType.monthly => PlanPeriod.monthly,
            PackageType.annual => PlanPeriod.annual,
            _ => PlanPeriod.other,
          },
          raw: p,
        ),
    ];
  }

  @override
  Future<PurchaseOutcome> purchase(PaywallPlan plan) async {
    final package = plan.raw;
    if (package is! Package) return PurchaseOutcome.failed;
    try {
      final info = await Purchases.purchasePackage(package);
      final premium = _isPremium(info);
      _controller.add(premium);
      return premium ? PurchaseOutcome.purchased : PurchaseOutcome.failed;
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        return PurchaseOutcome.cancelled;
      }
      debugPrint('Purchase failed: $code ${e.message}');
      return PurchaseOutcome.failed;
    }
  }

  @override
  Future<bool> restore() async {
    final info = await Purchases.restorePurchases();
    final premium = _isPremium(info);
    _controller.add(premium);
    return premium;
  }

  @override
  Future<void> dispose() async {
    final l = _listener;
    if (l != null) Purchases.removeCustomerInfoUpdateListener(l);
    await _controller.close();
  }

  static bool _isPremium(CustomerInfo info) =>
      info.entitlements.active.containsKey(AppRules.premiumEntitlementId);
}

/// Simulated store for testing the whole paywall flow before Google Play /
/// App Store are connected. Purchases are saved on the device and expire like a
/// real subscription (30 days monthly, 365 days annual). No money is involved.
///
/// Enabled with `--dart-define=MOCK_PURCHASES=true`, or automatically in debug
/// builds when no store key was given. The prices below are PLACEHOLDERS.
class MockEntitlementService implements EntitlementService {
  MockEntitlementService(this._prefs, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final SharedPreferences _prefs;
  final DateTime Function() _clock;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  static const _key = 'mock_subscription_v1';

  static const plans = <PaywallPlan>[
    PaywallPlan(
      identifier: r'$rc_annual',
      title: 'الاشتراك السنوي',
      priceString: '39.99 \$',
      priceAmount: 39.99,
      currencyCode: 'USD',
      period: PlanPeriod.annual,
      raw: null,
    ),
    PaywallPlan(
      identifier: r'$rc_monthly',
      title: 'الاشتراك الشهري',
      priceString: '4.99 \$',
      priceAmount: 4.99,
      currencyCode: 'USD',
      period: PlanPeriod.monthly,
      raw: null,
    ),
  ];

  bool get _active {
    final raw = _prefs.getString(_key);
    if (raw == null) return false;
    try {
      final m = jsonDecode(raw);
      final until = m is Map<String, dynamic>
          ? DateTime.tryParse('${m['until']}')
          : null;
      return until != null && _clock().isBefore(until);
    } on FormatException {
      return false;
    }
  }

  @override
  Stream<bool> get premiumChanges => _controller.stream;

  @override
  Future<void> init() async {}

  @override
  Future<bool> refresh() async => _active;

  @override
  Future<List<PaywallPlan>> loadPlans() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return plans;
  }

  @override
  Future<PurchaseOutcome> purchase(PaywallPlan plan) async {
    // Looks like a store sheet: a short wait, then success.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final days = plan.period == PlanPeriod.annual ? 365 : 30;
    final until = _clock().add(Duration(days: days));
    await _prefs.setString(_key,
        jsonEncode({'plan': plan.identifier, 'until': until.toIso8601String()}));
    _controller.add(true);
    return PurchaseOutcome.purchased;
  }

  @override
  Future<bool> restore() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final active = _active;
    _controller.add(active);
    return active;
  }

  /// Test helper (settings screen): drops the simulated subscription.
  Future<void> cancelMockSubscription() async {
    await _prefs.remove(_key);
    _controller.add(false);
  }

  @override
  Future<void> dispose() => _controller.close();
}

/// Used when there is no store key and mock mode is off (for example a release
/// build without keys). Everyone stays on the free plan; nothing can be bought.
class UnavailableEntitlementService implements EntitlementService {
  @override
  Stream<bool> get premiumChanges => const Stream<bool>.empty();

  @override
  Future<void> init() async {}

  @override
  Future<bool> refresh() async => false;

  @override
  Future<List<PaywallPlan>> loadPlans() async => const [];

  @override
  Future<PurchaseOutcome> purchase(PaywallPlan plan) async =>
      PurchaseOutcome.failed;

  @override
  Future<bool> restore() async => false;

  @override
  Future<void> dispose() async {}
}

/// Test double for unit tests: toggle premium by hand.
class DebugEntitlementService implements EntitlementService {
  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  bool _premium = false;

  @override
  Stream<bool> get premiumChanges => _controller.stream;

  @override
  Future<void> init() async {}

  @override
  Future<bool> refresh() async => _premium;

  @override
  Future<List<PaywallPlan>> loadPlans() async => MockEntitlementService.plans;

  @override
  Future<PurchaseOutcome> purchase(PaywallPlan plan) async {
    _setPremium(true);
    return PurchaseOutcome.purchased;
  }

  @override
  Future<bool> restore() async => _premium;

  void debugSetPremium(bool value) => _setPremium(value);

  void _setPremium(bool value) {
    _premium = value;
    _controller.add(value);
  }

  @override
  Future<void> dispose() => _controller.close();
}

/// Picks and initialises the right service:
///   1. mock mode requested (--dart-define=MOCK_PURCHASES=true), or a debug
///      build without store keys  -> [MockEntitlementService]
///   2. store key present          -> [RevenueCatEntitlementService]
///   3. otherwise                  -> [UnavailableEntitlementService]
/// If the store cannot start, the app still opens on the free plan and the
/// cached answer keeps paying users unlocked.
Future<EntitlementService> createEntitlementService(
    SharedPreferences prefs) async {
  final key = AppConfig.revenueCatApiKey;
  if (AppConfig.mockPurchases || (key.isEmpty && kDebugMode)) {
    return MockEntitlementService(prefs);
  }
  if (key.isNotEmpty) {
    final service = RevenueCatEntitlementService(apiKey: key);
    try {
      await service.init();
      return service;
    } on Object catch (e) {
      debugPrint('RevenueCat init failed: $e');
    }
  }
  return UnavailableEntitlementService();
}
