import 'package:flutter_test/flutter_test.dart';
import 'package:nihongo_salem/services/entitlement_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  late DateTime now;

  MockEntitlementService make() =>
      MockEntitlementService(prefs, clock: () => now);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    now = DateTime(2026, 5, 1);
  });

  test('offers an annual and a monthly plan', () async {
    final plans = await make().loadPlans();
    expect(plans.map((p) => p.period),
        containsAll([PlanPeriod.annual, PlanPeriod.monthly]));
    expect(plans.every((p) => p.priceAmount != null), isTrue);
  });

  test('not premium until something is bought', () async {
    expect(await make().refresh(), isFalse);
  });

  test('purchase makes the user premium, survives a restart', () async {
    final service = make();
    final changes = <bool>[];
    service.premiumChanges.listen(changes.add);
    final monthly = (await service.loadPlans())
        .firstWhere((p) => p.period == PlanPeriod.monthly);

    expect(await service.purchase(monthly), PurchaseOutcome.purchased);
    await Future<void>.delayed(Duration.zero);
    expect(changes, [true]);
    expect(await make().refresh(), isTrue); // new instance, same prefs
  });

  test('monthly expires after 30 days, annual lasts a year', () async {
    final plans = await make().loadPlans();
    final monthly = plans.firstWhere((p) => p.period == PlanPeriod.monthly);
    final annual = plans.firstWhere((p) => p.period == PlanPeriod.annual);

    await make().purchase(monthly);
    now = DateTime(2026, 5, 1).add(const Duration(days: 29));
    expect(await make().refresh(), isTrue);
    now = DateTime(2026, 5, 1).add(const Duration(days: 31));
    expect(await make().refresh(), isFalse);

    now = DateTime(2026, 5, 1);
    await make().purchase(annual);
    now = DateTime(2026, 5, 1).add(const Duration(days: 300));
    expect(await make().refresh(), isTrue);
  });

  test('restore returns the active state; cancel removes it', () async {
    final service = make();
    expect(await service.restore(), isFalse);
    await service.purchase((await service.loadPlans()).first);
    expect(await service.restore(), isTrue);
    await service.cancelMockSubscription();
    expect(await service.refresh(), isFalse);
  });
}
