import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/env_config.dart';
import '../../models/db_models.dart';
import '../../services/live_progress_tracker.dart';
import '../../services/notifications_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';
import '../mobile/mobile_shell.dart';
import 'provider_subscriptions_screen.dart';

class TowingDashboardScreen extends StatefulWidget {
  final CustomerProfile profile;
  final VoidCallback onRefreshProfile;
  final VoidCallback onSignedOut;
  final int initialTab;

  const TowingDashboardScreen({
    super.key,
    required this.profile,
    required this.onRefreshProfile,
    required this.onSignedOut,
    this.initialTab = 0,
  });

  @override
  State<TowingDashboardScreen> createState() => _TowingDashboardScreenState();
}

class _TowingDashboardScreenState extends State<TowingDashboardScreen> {
  final _db = Supabase.instance.client;
  final _tracker = LiveProgressTracker();
  final _notifs = NotificationsService();
  late int _tab = widget.initialTab;

  @override
  void dispose() {
    _tracker.stop();
    super.dispose();
  }

  void _goHome() {
    if (Navigator.canPop(context)) {
      Navigator.popUntil(context, (r) => r.isFirst);
    } else {
      Navigator.pushReplacement(
        context,
        animatedRoute(LiveMobileShell(
          profile: widget.profile,
          onRefreshProfile: widget.onRefreshProfile,
          onSignedOut: widget.onSignedOut,
        )),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final showPayments = EnvConfig.paymentsEnabled.value;
    if (!showPayments) {
      _tab = 0;
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        title: Text(
          'ونش الطوارئ · ${widget.profile.fullName ?? ""}',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        actions: [
          IconButton(
            tooltip: 'العودة للرئيسية',
            icon: const Icon(Icons.storefront),
            onPressed: _goHome,
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () => _notifs.openNotificationsSheet(context),
          ),
          if (showPayments)
            IconButton(
              icon: const Icon(Icons.workspace_premium, color: AppColors.orange),
              onPressed: () => Navigator.push(
                context,
                animatedRoute(ProviderSubscriptionsScreen(
                  currentPlanCode: widget.profile.subscriptionPlan,
                  onSubscribed: widget.onRefreshProfile,
                )),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _db.auth.signOut();
              if (context.mounted) {
                Navigator.popUntil(context, (r) => r.isFirst);
              }
              widget.onSignedOut();
            },
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        child: _tab == 0 ? _towingOrdersTab(showPayments) : _towingWalletTab(),
      ),
      bottomNavigationBar: showPayments
          ? BottomNavigationBar(
              currentIndex: _tab,
              selectedItemColor: AppColors.orange,
              onTap: (i) => setState(() => _tab = i),
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.local_shipping), label: 'طلبات الونش'),
                BottomNavigationBarItem(
                  icon: Icon(Icons.account_balance_wallet),
                  label: 'المحفظة',
                ),
              ],
            )
          : null,
    );
  }

  Widget _towingOrdersTab(bool showPayments) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _db
          .from('mechanic_requests')
          .stream(primaryKey: ['id'])
          .eq('service_type', 'winch')
          .order('created_at', ascending: false),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final orders = snap.data!.map(DbMechanicRequest.fromMap).toList();
        if (orders.isEmpty) {
          return const Center(child: Text('لا توجد طلبات ونش حالياً'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: orders.length,
          itemBuilder: (_, i) {
            final o = orders[i];
            return FadeSlideIn(
              index: i,
              child: Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'طلب سحب · ${o.carDetails}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          Chip(label: Text(o.progressStep)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Pickup: ${o.pickupLatitude?.toStringAsFixed(4)}, ${o.pickupLongitude?.toStringAsFixed(4)}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                      Text(
                        'Drop-off: ${o.dropoffAddress ?? "محددة على الخريطة"}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                      if (showPayments) ...[
                        const SizedBox(height: 6),
                        Text(
                          'الأجرة: ${o.totalAmount} د.أ',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.orange,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      if (o.status == 'pending')
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.orange,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => _acceptWinch(o),
                          child: const Text('قبول الطلب والانطلاق للعميل'),
                        ),
                      if (o.status == 'accepted' && o.mechanicId == widget.profile.id)
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => _completeWinch(o, showPayments),
                          child: const Text('تأكيد تسليم السيارة وإكمال الطلب'),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _acceptWinch(DbMechanicRequest o) async {
    await _db.from('mechanic_requests').update({
      'status': 'accepted',
      'progress_step': 'on_the_way',
      'mechanic_id': widget.profile.id,
    }).eq('id', o.id);

    if (o.userId != null) {
      await _notifs.sendNotification(
        targetUserId: o.userId!,
        title: 'ونش الطوارئ في طريقه إليك',
        body: 'تم قبول طلبك، السائق يتحرك الآن نحو موقعك.',
        type: 'order_accepted',
        referenceId: o.id,
      );
      if (o.pickupLatitude != null && o.pickupLongitude != null) {
        _tracker.startTrackingEmergencyArrival(
          requestId: o.id,
          customerUserId: o.userId!,
          serviceType: 'winch',
          pickupLat: o.pickupLatitude!,
          pickupLng: o.pickupLongitude!,
        );
      }
    }
  }

  Future<void> _completeWinch(DbMechanicRequest o, bool showPayments) async {
    final rate = widget.profile.commissionRate;
    final comm = showPayments ? o.totalAmount * rate : 0.0;
    final net = showPayments ? o.totalAmount - comm : 0.0;

    await _db.from('mechanic_requests').update({
      'status': 'completed',
      'progress_step': 'completed',
      'commission_amount': comm,
      'payment_status': 'paid',
    }).eq('id', o.id);

    if (showPayments) {
      await _db.from('wallet_transactions').insert({
        'provider_id': widget.profile.id,
        'customer_id': o.userId,
        'reference_id': o.id,
        'transaction_type': 'winch_towing',
        'payment_method': 'cash',
        'gross_amount': o.totalAmount,
        'commission_rate': rate,
        'commission_amount': comm,
        'net_amount': net,
        'status': 'completed',
      });
    }
  }

  Widget _towingWalletTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _db
          .from('wallet_transactions')
          .stream(primaryKey: ['id'])
          .eq('provider_id', widget.profile.id)
          .order('created_at', ascending: false),
      builder: (context, snap) {
        final txs = (snap.data ?? []).map(DbWalletTransaction.fromMap).toList();
        final net = txs.fold(0.0, (s, t) => s + t.netAmount);
        final gross = txs.fold(0.0, (s, t) => s + t.grossAmount);
        final comm = txs.fold(0.0, (s, t) => s + t.commissionAmount);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.navy,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('صافي محفظة الونش', style: TextStyle(color: Colors.white70)),
                  Text(
                    '${net.toStringAsFixed(2)} د.أ',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'قبل العمولة: ${gross.toStringAsFixed(2)} | العمولة: ${comm.toStringAsFixed(2)} د.أ',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ...txs.map((t) => Card(
                  child: ListTile(
                    title: Text('رحلة ونش #${t.referenceId?.substring(0, 6) ?? ""}'),
                    subtitle: Text(
                      'قبل العمولة: ${t.grossAmount} · العمولة: -${t.commissionAmount.toStringAsFixed(2)}',
                    ),
                    trailing: Text(
                      '+${t.netAmount.toStringAsFixed(2)} د.أ',
                      style: const TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                )),
          ],
        );
      },
    );
  }
}